# OrgOS Dashboard アーキテクチャ設計書

**ステータス**: 設計完了
**作成日**: 2026-03-30
**関連タスク**: T-OS-060
**フェーズ**: Phase 1（閲覧のみ MVP）

---

## 1. システム概要

複数リポジトリで OrgOS を運用する際に、全プロジェクトの状態を一元的に把握するための Web ダッシュボード。
独立リポジトリとして管理し、OrgOS 側の `/org-dashboard` コマンドでプロジェクトを登録する。

### 1.1 全体構成図（データフロー）

```
各プロジェクトリポジトリ              ホームディレクトリ           Dashboard サーバー
─────────────────────────          ──────────────────          ──────────────────────
  repo-a/                            ~/.orgos/                    localhost:3000
    .ai/                               projects.yaml  ──読み取り──▶  Next.js App
      CONTROL.yaml  ─── /org-publish ──▶  (パス登録)                   │
      TASKS.yaml         (パス追記)                                      │ fs.watch
      DASHBOARD.md                                               ─────▼─────────────
      RUNTIME.yaml    ───────────────────────────────────────▶  ファイル直接読み取り
                                                                 (projects.yaml 経由)
  repo-b/                                                               │
    .ai/                                                                │ Server-Sent Events
      CONTROL.yaml  ─── /org-publish ──▶ (パス追記)                     │ または polling
      TASKS.yaml                                                         ▼
      DASHBOARD.md                                               ブラウザ (Chrome 等)
      RUNTIME.yaml  ──────────────────────────────────────────▶  一覧画面 / 詳細画面
```

### 1.2 コンポーネント構成

```
orgos-dashboard/                  # 独立リポジトリ
├── app/                          # Next.js App Router
│   ├── page.tsx                  # プロジェクト一覧画面
│   ├── projects/[id]/page.tsx    # プロジェクト詳細画面
│   └── api/
│       ├── projects/route.ts     # プロジェクト一覧 API
│       ├── projects/[id]/route.ts# プロジェクト詳細 API
│       └── events/route.ts       # SSE エンドポイント（リアルタイム更新）
├── lib/
│   ├── reader.ts                 # .ai/ ファイル読み取りロジック
│   ├── parser.ts                 # YAML/Markdown パーサー
│   ├── watcher.ts                # ファイル変更監視
│   └── aggregator.ts             # データ集約・正規化
├── components/
│   ├── ProjectCard.tsx           # プロジェクトカード
│   ├── ProjectDetail.tsx         # 詳細パネル
│   ├── StageProgress.tsx         # ステージ進捗バー
│   ├── TaskSummary.tsx           # タスクサマリー
│   └── BlockerAlert.tsx          # ブロッカー表示
└── types/
    └── index.ts                  # 型定義
```

---

## 2. 技術スタック選定

| レイヤー | 技術 | バージョン | 選定理由 |
|----------|------|-----------|----------|
| フレームワーク | Next.js (App Router) | 15.x | フルスタック1リポジトリで完結。SSR/SSE が容易。デプロイ先の選択肢が広い |
| UI ライブラリ | shadcn/ui + Tailwind CSS | 最新 | ゼロ依存のコピー型コンポーネント。カスタマイズが容易 |
| YAML パーサー | js-yaml | 4.x | 実績あり。OrgOS の YAML 構造と互換性が高い |
| Markdown パーサー | unified + remark | 最新 | DASHBOARD.md の Markdown を AST として読み取るため |
| ファイル監視 | chokidar | 3.x | Node.js の fs.watch より安定。クロスプラットフォーム対応 |
| リアルタイム | Server-Sent Events (SSE) | Web 標準 | WebSocket より軽量。読み取り専用なので SSE で十分 |
| ランタイム | Node.js | 20 LTS | ファイルシステムアクセスが必要。ブラウザ外で動作 |
| 型定義 | TypeScript | 5.x | 型安全。YAML スキーマの型定義が容易 |

### 選定の根拠

- **Next.js を選ぶ理由**: API と UI を同一プロセスで動かせる。`localhost:3000` の1コマンド起動で完結する。Vercel にそのままデプロイできる
- **Vite + Express を選ばない理由**: 2プロセス管理が必要になり、セットアップコストが上がる
- **Electron を選ばない理由**: インストール不要（`npx orgos-dashboard` または `npm run dev` で起動）の方が導入が容易

---

## 3. データモデル

### 3.1 `~/.orgos/projects.yaml` スキーマ

```yaml
# OrgOS Dashboard プロジェクト登録ファイル
# /org-publish コマンドが自動管理する
version: "1"
projects:
  - id: "my-app"                          # プロジェクト識別子（ディレクトリ名から自動生成）
    name: "My App"                         # 表示名（CONTROL.yaml の project_name から取得）
    path: "/Users/alice/Dev/my-app"        # リポジトリの絶対パス
    registered_at: "2026-03-30T10:00:00Z" # /org-publish 実行日時
    last_published_at: "2026-03-30T10:00:00Z" # 最後に publish した日時

  - id: "another-project"
    name: "Another Project"
    path: "/Users/alice/Dev/another-project"
    registered_at: "2026-03-29T09:00:00Z"
    last_published_at: "2026-03-29T09:00:00Z"
```

### 3.2 各プロジェクトから抽出するデータ

#### CONTROL.yaml から取得するフィールド

| フィールド | 用途 |
|-----------|------|
| `project_name` | 表示名 |
| `stage` | 現在のステージ（KICKOFF / REQUIREMENTS / ... / RELEASE） |
| `paused` | 一時停止中フラグ |
| `awaiting_owner` | Owner 回答待ちフラグ |
| `gates` | ゲート通過状況 |

#### TASKS.yaml から取得するフィールド

| フィールド | 用途 |
|-----------|------|
| `tasks[].status` | タスクの状態（queued / running / blocked / review / done） |
| `tasks[].title` | タスクタイトル（ブロッカー表示用） |
| `tasks[].id` | タスク ID |
| `tasks[].deps` | 依存関係（ブロッカー判定用） |

集約計算:
- `total_tasks`: `tasks` の件数
- `done_tasks`: `status == "done"` の件数
- `running_tasks`: `status == "running"` の件数
- `blocked_tasks`: `status == "blocked"` の件数
- `progress_percent`: `done_tasks / total_tasks * 100`
- `blockers`: `status == "blocked"` のタスク一覧

#### DASHBOARD.md から取得するフィールド

| セクション | 用途 |
|-----------|------|
| `## Next Action (Owner)` セクション | 次のアクション文言 |

#### RUNTIME.yaml から取得するフィールド

| フィールド | 用途 |
|-----------|------|
| `tick_count` | Tick 実行回数（アクティビティ指標） |

### 3.3 集約後のデータ構造（API レスポンス型）

```typescript
// types/index.ts

export type Stage =
  | "KICKOFF"
  | "REQUIREMENTS"
  | "DESIGN"
  | "IMPLEMENTATION"
  | "INTEGRATION"
  | "RELEASE";

export type TaskStatus = "queued" | "running" | "blocked" | "review" | "done";

export interface ProjectSummary {
  id: string;                      // projects.yaml の id
  name: string;                    // CONTROL.yaml の project_name
  path: string;                    // リポジトリの絶対パス
  stage: Stage;                    // 現在のステージ
  paused: boolean;                 // 一時停止中
  awaiting_owner: boolean;         // Owner 回答待ち
  progress: {
    total: number;                 // タスク総数
    done: number;                  // 完了タスク数
    running: number;               // 実行中タスク数
    blocked: number;               // ブロック中タスク数
    percent: number;               // 進捗率（0-100）
  };
  blockers: BlockerItem[];         // ブロッカータスク一覧
  tick_count: number;              // Tick 実行回数
  next_action: string | null;      // DASHBOARD.md から抽出した次のアクション
  last_updated_at: string;         // ファイルの最終更新日時（fs.stat から取得）
  registered_at: string;           // /org-publish で登録した日時
}

export interface BlockerItem {
  id: string;                      // タスク ID
  title: string;                   // タスクタイトル
  deps: string[];                  // 依存タスク ID
}

export interface ProjectDetail extends ProjectSummary {
  gates: {
    kickoff_complete: boolean;
    requirements_approved: boolean;
    design_approved: boolean;
    integration_approved: boolean;
    release_approved: boolean;
  };
  tasks: TaskItem[];               // 全タスク一覧
}

export interface TaskItem {
  id: string;
  title: string;
  status: TaskStatus;
  deps: string[];
  owner_role: string;
}
```

---

## 4. UI 設計（Phase 1 MVP）

### 4.1 画面構成

```
┌─────────────────────────────────────────────────────────┐
│  OrgOS Dashboard                          [最終更新: 10秒前] │
├─────────────────────────────────────────────────────────┤
│  プロジェクト一覧 (/)                                        │
│                                                         │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────┐ │
│  │ my-app         │  │ another-proj   │  │ api-server │ │
│  │ IMPLEMENTATION │  │ DESIGN         │  │ RELEASE    │ │
│  │ ████████░░ 78% │  │ ████░░░░░░ 40% │  │ ██████████ │ │
│  │ ⚠ ブロッカー 2  │  │ ✓ 正常         │  │ ✓ 正常     │ │
│  │ 12/15 タスク   │  │ 6/15 タスク    │  │ 15/15 完了 │ │
│  └────────────────┘  └────────────────┘  └────────────┘ │
│                                                         │
│  詳細画面 (/projects/[id])                                  │
│                                                         │
│  my-app — IMPLEMENTATION ステージ                          │
│  ─────────────────────────────                          │
│  ステージ進捗:                                              │
│  [KICKOFF]✓ [REQUIREMENTS]✓ [DESIGN]✓ [IMPL]▶ [INTEG] [RELEASE] │
│                                                         │
│  タスクサマリー:                                            │
│  完了 12 / 実行中 1 / ブロック 2 / 待機 0                    │
│                                                         │
│  ⚠ ブロッカー:                                             │
│  T-031 認証モジュール実装  (deps: T-030 待ち)               │
│  T-033 E2E テスト実行      (deps: T-031 待ち)               │
│                                                         │
│  次のアクション: /org-tick で T-030 を実行                   │
└─────────────────────────────────────────────────────────┘
```

### 4.2 プロジェクトカードの表示項目

| 表示項目 | データソース | 備考 |
|---------|------------|------|
| プロジェクト名 | `project_name` (CONTROL.yaml) | |
| 現在のステージ | `stage` (CONTROL.yaml) | バッジで色分け |
| 進捗バー + % | 計算値 `done/total` (TASKS.yaml) | |
| タスク数 | `done / total` (TASKS.yaml) | |
| ブロッカー件数 | `blocked` (TASKS.yaml) | 0件なら非表示 |
| Owner 回答待ち | `awaiting_owner` (CONTROL.yaml) | バッジ表示 |
| 一時停止中 | `paused` (CONTROL.yaml) | バッジ表示 |
| 最終更新 | `last_updated_at` (fs.stat) | 相対時間表示 |

### 4.3 プロジェクト詳細画面の表示項目

| セクション | 表示項目 |
|-----------|---------|
| ステージ進捗 | 全ステージ（KICKOFF〜RELEASE）のバッジ。完了済みはチェック、現在は強調、未来はグレー |
| ゲート状態 | gates の各フラグ（kickoff_complete 等）を一覧表示 |
| タスクサマリー | done / running / blocked / queued の件数 |
| ブロッカー一覧 | blocked タスクの id / title / 依存関係 |
| タスク一覧 | 全タスクを status でフィルタリング可能 |
| 次のアクション | DASHBOARD.md から抽出したテキスト |
| Tick 実行回数 | `tick_count` (RUNTIME.yaml) |

### 4.4 ステージ別バッジカラー

| ステージ | 色 |
|---------|-----|
| KICKOFF | グレー |
| REQUIREMENTS | ブルー |
| DESIGN | パープル |
| IMPLEMENTATION | オレンジ |
| INTEGRATION | シアン |
| RELEASE | グリーン |

---

## 5. `/org-dashboard` コマンド仕様

### 5.1 配置場所

```
.claude/commands/org-publish.md  # OrgOS リポジトリに追加
```

### 5.2 実行時の動作

```
1. CONTROL.yaml を読み取り project_name を取得
2. カレントディレクトリの絶対パスを取得
3. ~/.orgos/ ディレクトリが存在しなければ作成
4. ~/.orgos/projects.yaml が存在しなければ初期化
5. 重複チェック（同一パスが登録済みかどうか）
6. 未登録なら projects.yaml にエントリを追記
7. 登録済みなら last_published_at を更新
8. 完了メッセージを表示
```

### 5.3 `~/.orgos/projects.yaml` への登録フォーマット

新規登録時に追記するエントリ:

```yaml
- id: "<ディレクトリ名をケバブケースに変換>"
  name: "<CONTROL.yaml の project_name>"
  path: "<カレントディレクトリの絶対パス>"
  registered_at: "<ISO 8601 形式の日時>"
  last_published_at: "<ISO 8601 形式の日時>"
```

`id` の生成規則:
- カレントディレクトリ名をそのまま使用
- スペースはハイフンに置換
- 英小文字に統一
- 例: `My App` → `my-app`

### 5.4 重複チェックのロジック

```
1. projects.yaml の全エントリの path フィールドと比較
2. 同一パスが存在する場合 → 上書き更新（last_published_at のみ更新）
3. 存在しない場合 → 新規追加
4. project_name が変わっていた場合は name も更新する
```

### 5.5 出力例

```
# 新規登録の場合
OrgOS Dashboard に登録しました

  プロジェクト: My App
  パス: /Users/alice/Dev/my-app
  登録ファイル: ~/.orgos/projects.yaml

Dashboard の起動: https://github.com/orgos-dev/orgos-dashboard

# 更新の場合
OrgOS Dashboard の登録情報を更新しました

  プロジェクト: My App
  最終更新: 2026-03-30T10:00:00Z
```

### 5.6 `org-publish.md` コマンド定義（抜粋）

```markdown
# /org-publish

OrgOS Dashboard にこのプロジェクトを登録します。

## 動作

1. CONTROL.yaml から project_name を取得
2. ~/.orgos/projects.yaml に現在のリポジトリパスを登録
3. 既に登録済みの場合は last_published_at を更新

## 実行後

Dashboard サーバーが起動していれば、自動的にプロジェクトが表示されます。
```

---

## 6. Phase 2 拡張ポイント

Phase 2 では、Dashboard の UI から各プロジェクトに対して指示を送れるようにする。

### 6.1 指示機能のインターフェース設計

**方式**: Dashboard サーバーが各プロジェクトのリポジトリに対してシェルコマンドを実行する。

```typescript
// app/api/actions/route.ts (Phase 2 追加予定)

export interface ActionRequest {
  project_id: string;              // 対象プロジェクト
  action: ActionType;              // 実行するアクション
  params?: Record<string, string>; // アクション固有パラメータ
}

export type ActionType =
  | "org-tick"                     // 次のタスクを実行
  | "org-tick-with-comment"        // コメント付きで実行
  | "custom";                      // 任意コマンド（将来用）

export interface ActionResult {
  project_id: string;
  action: ActionType;
  status: "started" | "completed" | "failed";
  output?: string;                 // コマンド実行結果
  started_at: string;
  completed_at?: string;
}
```

**実行方式**:

```
Dashboard サーバー (Node.js)
  ↓ child_process.spawn
claude -p "/org-tick" --cwd /path/to/project
  ↓ stdout/stderr を SSE でブラウザに転送
ブラウザ
```

### 6.2 Phase 2 追加コンポーネント

```
app/
  api/
    actions/route.ts          # POST: アクション実行エンドポイント
    actions/[id]/route.ts     # GET: アクション実行状態確認
components/
  ActionButton.tsx             # Tick 実行ボタン
  ActionLog.tsx                # 実行ログストリーム表示
```

### 6.3 Phase 2 の前提条件

- Dashboard サーバーが実行されているマシンに `claude` コマンドがインストールされていること
- 各プロジェクトリポジトリへの読み書きアクセス権があること
- セキュリティ: ローカルネットワーク限定（外部公開時は認証が必須）

---

## 7. 実装優先度とモジュール所有権

### Phase 1 実装順序

| 優先度 | モジュール | 説明 |
|--------|-----------|------|
| 1 | `lib/reader.ts` + `lib/parser.ts` | ファイル読み取りとパース。他の全モジュールの基盤 |
| 2 | `app/api/projects/route.ts` | プロジェクト一覧 API |
| 3 | `app/page.tsx` + `components/ProjectCard.tsx` | 一覧画面 |
| 4 | `lib/watcher.ts` + `app/api/events/route.ts` | リアルタイム更新（SSE） |
| 5 | `app/projects/[id]/page.tsx` | 詳細画面 |
| 6 | `.claude/commands/org-publish.md` | /org-publish コマンド |

### Contract（モジュール間インターフェース）

並列開発のための境界定義:

```typescript
// lib/reader.ts が提供するインターフェース
export interface ProjectReader {
  readProjectsYaml(path: string): Promise<ProjectsConfig>;
  readControlYaml(projectPath: string): Promise<ControlConfig>;
  readTasksYaml(projectPath: string): Promise<TasksConfig>;
  readRuntimeYaml(projectPath: string): Promise<RuntimeConfig>;
}

// lib/aggregator.ts が提供するインターフェース
export interface ProjectAggregator {
  aggregate(
    entry: ProjectEntry,
    control: ControlConfig,
    tasks: TasksConfig,
    runtime: RuntimeConfig
  ): ProjectSummary;
}
```

---

## 8. リスクとトレードオフ

### リスク

| リスク | 影響 | 緩和策 |
|--------|------|--------|
| ファイル読み取り権限がない | プロジェクトが表示されない | エラーをカードに表示し、他プロジェクトは継続表示 |
| YAML フォーマットが壊れている | パースエラー | try-catch でラップし、エラー状態のカードとして表示 |
| TASKS.yaml が大きすぎる | 読み取りが遅い | ファイルサイズ上限チェックを追加（1MB 超は警告） |
| `~/.orgos/` が存在しない | Dashboard 起動時にエラー | 初回起動時に自動作成。projects.yaml が空でも動作する |
| Phase 2 でのコマンド実行リスク | 意図しない変更 | ローカル限定 + 確認ダイアログ + ドライラン機能を提供予定 |

### トレードオフ

| 決定 | 理由 | 代替案 |
|------|------|--------|
| ファイル直接読み取り方式 | プロジェクト側に変更不要。シンプル | SQLite へのエクスポート方式（複雑だが高速） |
| SSE によるリアルタイム更新 | 実装が簡単。読み取り専用に適切 | WebSocket（双方向通信が必要な Phase 2 で採用を検討） |
| Next.js App Router | サーバー/クライアントを1つのプロジェクトで管理 | Express + React（構成が分かれて複雑化） |
| chokidar によるファイル監視 | 安定性と互換性が高い | Node.js fs.watch（低水準で不安定なケースあり） |
