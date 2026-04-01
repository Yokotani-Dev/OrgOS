# プロジェクトフロールール

> OrgOS フローの優先、スコープ制限、タスク規模判定

---

## 最優先ルール：OrgOS フロー優先

**新規セッションでも、スラッシュコマンド以外の依頼でも、必ず OrgOS フローで処理する。**

### セッション開始時の行動

1. **まず `.ai/TASKS.yaml` を確認する**
   - 進行中のプロジェクトがあるか？
   - 現在のフェーズは？
   - 未完了タスクは？

2. **依頼を OrgOS タスクとして認識する**
   - Claude Code のネイティブ Plan モード（EnterPlanMode）は**使用しない**
   - 代わりに `.ai/TASKS.yaml` に追加して管理する

3. **既存プロジェクトがある場合**
   - 依頼が既存タスクに関連するか判断
   - 関連あり → 該当タスクの一部として処理
   - 関連なし → 新規タスクとして追加

### EnterPlanMode を使わない理由

| Claude Code Plan モード | OrgOS フロー |
|------------------------|--------------|
| セッション内で完結 | 永続化（TASKS.yaml） |
| 履歴が残らない | DECISIONS.md に記録 |
| 他セッションと連携不可 | どのセッションからも参照可能 |

### 例外

以下の場合のみ OrgOS フロー外で対応してよい：

- OrgOS 自体についての質問（「OrgOS って何？」など）
- 単発の情報提供（「TypeScript の型の書き方教えて」など）
- プロジェクトと無関係な雑談

---

## プロジェクトスコープ制限

**このリポジトリが OrgOS 開発用の場合、OrgOS と無関係な依頼は受け付けない。**

### スコープ確認

依頼を受けたら、まず `CONTROL.yaml` の `project_scope` を確認:

```yaml
project_scope: "OrgOS development only"  # OrgOS 開発ディレクトリの場合
```

### スコープ内の判定基準

| 依頼 | 判定 |
|------|------|
| OrgOS の機能追加・修正 | ✅ スコープ内 |
| OrgOS のドキュメント更新 | ✅ スコープ内 |
| OrgOS の改善提案（OIP） | ✅ スコープ内 |
| OrgOS を使った別プロジェクト開発 | ❌ スコープ外 |
| Azure Function など別システムの診断 | ❌ スコープ外 |
| 一般的なプログラミング質問 | 🟡 単発ならOK |

### スコープ外の依頼を受けた場合

**必ず Owner に確認する:**

```
⚠️ スコープ外の依頼を検出しました

依頼内容: 「[依頼内容]」
このリポジトリのスコープ: 「OrgOS development only」

以下のいずれかを選んでください:

[A] 別のディレクトリで作業する
    → OrgOS と無関係なプロジェクトは別ディレクトリで管理することを推奨

[B] OrgOS の改善として扱う
    → この依頼が OrgOS に関連する場合のみ（例: OrgOS の機能追加）

[C] スコープを一時的に拡張する
    → CONTROL.yaml の project_scope を更新（推奨しない）

どれにしますか？
```

**Owner 承認なしに進めてはいけない。**

---

## タスク規模の判定

### 最重要ルール: 全作業 TASKS.yaml 登録必須

**規模に関わらず、全ての作業を TASKS.yaml に登録してから実行する。**
ad-hoc 実行（TASKS.yaml を経由せず直接作業すること）は禁止。

```
❌ 禁止: 依頼を受けてそのまま実行する
✅ 必須: 依頼 → TASKS.yaml に登録 → 実行 → 完了記録
```

### 依頼受付時の必須チェック（重要）

依頼を受けたら、**以下を必ず実行:**

```
1. ✅ プロジェクトスコープ確認
   - CONTROL.yaml の project_scope を確認
   - スコープ外なら Owner に確認（即実行禁止）

2. ✅ タスク規模を判定
   - 小: 1ファイル、他に影響なし
   - 中: 複数ファイル、設計判断あり
   - 大: 新機能、アーキテクチャ変更

3. ✅ TASKS.yaml に登録（全規模共通）
   - 小タスクでも必ず登録する
   - deps を設定する（進行中タスクとの関係を明確化）
   - 登録完了後に実行

4. ✅ 台帳を更新
   - TASKS.yaml: タスク追加
   - 中〜大: DECISIONS.md に PLAN-UPDATE-XXX として記録
   - STATUS.md / DASHBOARD.md: 更新
```

### 判断基準

| 規模 | 基準 | 対応 |
|------|------|------|
| 小 | 1ファイル以内、他タスクに影響なし | TASKS.yaml 登録 → 同一 Tick 内で実行 → done |
| 中 | 複数ファイル or 設計判断あり | TASKS.yaml 登録 + DECISIONS.md 記録 → 次 Tick で実行 |
| 大 | 新機能、アーキテクチャ変更 | PROJECT/BRIEF から計画 |

### 小タスクの処理

```
1. TASKS.yaml に登録（status: queued, deps 設定）
2. 同一 Tick 内で実行
3. TASKS.yaml を done に更新
4. STATUS.md の RUN_LOG に記録
5. 完了報告 + 次のステップ案内
```

### 中〜大タスクの処理

```
1. 「計画に組み込みます」と説明
2. TASKS.yaml に追加（deps で他タスクとの関係を明示）
3. DECISIONS.md に PLAN-UPDATE-XXX として記録
4. /org-tick で実行を案内
```

### 例

```
User: 「このファイルにログ出力追加して」

Manager:
  → 小タスクと判定
  → TASKS.yaml に T-FIX-XXX として登録（status: queued）
  → 実行 → done に更新
  → STATUS.md に記録
  → 完了報告 + 次のステップ案内
```

```
User: 「認証機能をJWTに変更して」

Manager:
  → 大タスクと判定
  → 「計画に組み込みます」と説明
  → TASKS.yaml に追加、deps で既存タスクとの関係を設定
  → DECISIONS.md に PLAN-UPDATE-XXX 記録
  → /org-tick で実行を案内
```

---

## 割り込みタスク受付フロー

**進行中のタスクがある状態で新しい依頼を受けた場合、Manager が自律的に管理する。**

### フロー

```
1. 新しい依頼を受ける

2. allowed_paths の衝突チェック（Iron Law: 必須）
   - 衝突なし → deps: [] で並列実行
   - 衝突あり → deps に先行タスクを自動追加（シリアル実行）
   - allowed_paths 未設定 → 並列実行禁止

3. TASKS.yaml に登録 → 即実行（Owner の確認不要）
```

### 衝突防止（Iron Law）

> **鉄則: allowed_paths が重複するタスクは絶対に並列実行しない。**

```
衝突判定ルール:
  - 完全一致: src/auth/ == src/auth/ → 衝突
  - 包含関係: src/ contains src/auth/ → 衝突
  - ファイル vs ディレクトリ: src/auth/login.ts in src/auth/ → 衝突
  - allowed_paths 未設定 → 全タスクと衝突とみなす
```

---

## スラッシュコマンド以外の依頼への対応

### 原則

**個別のプロンプトも OrgOS の制御下に取り込む。TASKS.yaml に登録して即実行する。Owner の確認は不要。**

ユーザーがスラッシュコマンドを使わずに依頼してきた場合：

1. **TASKS.yaml に登録** → 即実行 → 完了記録 → 次のタスクへ

スコープ外の依頼のみ Owner に確認する。それ以外は自律的に処理する。

---

## ルーティンワーク検出と Runbook 化

### 原則

**同じ種類の作業を2回以上実行したら、Runbook 化する。Runbook がある作業は必ず Runbook に従う。**

### ルーティン検出

以下のキーワードを含むタスクはルーティン候補:
- デプロイ / deploy
- リリース / release
- マイグレーション / migration
- セットアップ / setup
- バックアップ / backup
- ロールバック / rollback

### Runbook 実行ルール

1. **タスク実行前に `.ai/RUNBOOKS/` を確認** — 対応する Runbook があれば、それに従って実行
2. **Runbook に従って実行中に問題を発見したら** — Runbook 自体を更新する（場当たり的な回避は禁止）
3. **2回目の実行で Runbook がなければ自動作成** — `TEMPLATE.md` をベースに作成

### 禁止事項

- Runbook がある作業を自己流で実行すること
- Runbook の手順をスキップすること
- 問題を場当たり的に回避して Runbook を更新しないこと

---

## 参考資料

- [CLAUDE.md](../../CLAUDE.md)
- [.ai/CONTROL.yaml](../../.ai/CONTROL.yaml)
- [.ai/TASKS.yaml](../../.ai/TASKS.yaml)
