# Central Activity Ledger — 設計書 (T-OS-481)

> Owner 注文 (2026-06-10): 「OrgOS は GitHub 上のリポジトリをクローンして、いろんなリポジトリに分散するから、
> 私が実行したことについては、1つの DB みたいなものに実行ログがまとめられて、
> 私が OrgOS でやったことが 1 つのログに集約され、その日考えたことや実行したことが一覧になるようにする機能を作りたい」

- status: confirmed
- confirmed_by: Owner（2026-06-10「いいと思う！」— UI モック + 案 A: orgos-dashboard へ Journal 画面追加、を承認）
- confirmed_at: 2026-06-10
- review_trail: 実装前ゲート発動（Owner 指示）→ 設計提示 → MCP 要件追加 → UI モック提示 → 案 A 承認
- quality_level: mvp
- related_tasks: T-OS-481 (設計) / T-OS-482 (実装) / T-OS-483 (テスト)

---

## 1. 問題

| 現状のデータ | 場所 | 限界 |
|---|---|---|
| kernel イベント (orgos-event.v1) | 各リポジトリの `.ai/events/*.jsonl` | リポジトリ内に閉じている。横断ビューなし |
| セッションログ | 各リポジトリの `.ai/sessions/*.md` | ほぼ空テンプレ。横断不可 |
| RUN_LOG / DECISIONS | 各リポジトリの `.ai/` | 手動更新・形式バラバラ・横断不可 |
| プロジェクトレジストリ | `~/.orgos/projects.yaml` | 2 件のみで陳腐化。ログ機能なし |

**Owner は「今日、全リポジトリで何をやったか・何を考えたか」を 1 箇所で見る手段を持たない。**

### Owner レビュー結果 (2026-06-10)

| 論点 | Owner 回答 | 設計への反映 |
|---|---|---|
| ストア形式 | （技術判断は Manager に委任） | JSONL を SSOT に採用（下記 TECH-DECISION 参照） |
| 同期・参照範囲 | **「MCP で参照できるものがいいな」** | 要件 R6 追加: MCP サーバ経由でどこからでもジャーナル参照可能に（§4.7） |
| 思考ログの記録 | Manager 自動 + Owner 手動の両方（推奨案を採用） | §4.5 の記録規約どおり |
| 閲覧方法 | **将来 orgos-dashboard (Web UI) 連携前提** | スキーマを dashboard が読みやすい形に固定 + MCP の query 出力を JSON でも提供（§8） |

### TECH-DECISION: ストア形式は JSONL（DECISIONS.md 追記ツール不在のためここに記録）

**平易な説明**: ログは「1 行 = 1 イベント」のテキストファイルに**追記だけ**していく方式（JSONL）。
月ごとにファイルを分ける。データベースサーバは使わない。

- **理由1**: 複数のリポジトリ・セッションが同時に書き込んでも壊れにくい（追記専用なので）
- **理由2**: 壊れても 1 行壊れるだけで残りは無事（DB ファイルは丸ごと壊れることがある）
- **理由3**: あとから「検索を速くする索引（SQLite 等）」を追加でき、その場合も元データはこのテキストのまま
- **トレードオフ**: 複雑な検索は遅い → イベント数が増えたら v2 で索引を追加（MCP/journal の使用感に影響なし）

## 2. あるべき姿

```
リポジトリA (OrgOS clone) ──┐
リポジトリB (OrgOS clone) ──┼──▶ ~/.orgos/activity/events-YYYYMM.jsonl  ──▶ /org-journal
リポジトリC (OrgOS clone) ──┘        (中央ストア・追記専用・SSOT)            「今日の一覧」
```

- どのリポジトリで作業しても、イベントが **Owner のホーム配下の単一ストア** に追記される
- `/org-journal`（または `journal.sh today`）で **日次ダイジェスト**（実行したこと/考えたこと、リポジトリ別）が出る
- 既存の kernel イベント (`.ai/events/`) は **ブリッジで自動取り込み**（二重計装しない）

## 3. ストア設計

### SSOT: `~/.orgos/activity/events-YYYYMM.jsonl`

- **追記専用 JSONL・月次シャード**。DB サーバ不要、git 不要、破損耐性が高い
- 1 イベント = 1 行 = 1 回の `write()`（O_APPEND、4KB 未満）→ 複数リポジトリ/セッションからの同時追記でも実用上アトミック
- SQLite は v2 でクエリ用インデックス（再構築可能キャッシュ）として検討。SSOT は常に JSONL

### スキーマ: `orgos-activity.v1`

```json
{
  "schema_version": "orgos-activity.v1",
  "event_id": "ACT-20260610T120000Z-a1b2c3d4",
  "ts": "2026-06-10T12:00:00Z",
  "repo": {"name": "OrgOS", "path": "/Users/.../OrgOS", "remote": "github.com/owner/OrgOS"},
  "branch": "main",
  "session_id": "<claude session id or empty>",
  "actor": {"role": "manager", "id": "claude-manager"},
  "event_type": "session_start",
  "task_id": "",
  "title": "1行サマリ（日次一覧に表示される行）",
  "detail": "",
  "source": "hook",
  "origin_event_id": ""
}
```

- `event_type` enum: `session_start | session_end | task_created | task_done | decision | note | thought | commit | tick | release | kernel`
- `source` enum: `hook | cli | kernel-bridge`
- `origin_event_id`: kernel-bridge 取り込み時の元 event_id（重複取り込み防止キー）
- 「考えたこと」= `decision | note | thought`、「実行したこと」= それ以外、としてダイジェストで分類

### 補助ファイル

- `~/.orgos/activity/repos.json` — writer が自動 upsert するリポジトリ台帳（name/path/remote/last_seen）
- `~/.orgos/activity/cursors/<repo-key>.json` — ブリッジの取り込みカーソル（最後に取り込んだ event_id/行数）
- `~/.orgos/activity/errors.log` — writer の失敗ログ（hook を絶対にブロックしないため）

## 4. コンポーネント（すべて `scripts/activity/` に自己完結）

> **自己完結が必須**: `.orgos-manifest.yaml` の publish 対象は限定的で、配布先クローンには `scripts/org/` が存在しない。
> `scripts/activity/` は python3 stdlib + bash のみに依存し、他の scripts/ を source しない。

### 4.1 `scripts/activity/log-event.sh` (writer)

```
log-event.sh --type <event_type> --title <text> [--task-id T-XXX] [--detail <text>]
             [--actor-role manager] [--actor-id claude-manager] [--source cli]
             [--stdin-hook]   # hook 用: stdin の JSON から session_id を抽出
```

- repo name/remote/branch を git から自動検出（git 外なら dirname/empty）
- **必ず exit 0**（失敗は errors.log へ）— hook をブロックしない
- 簡易 secret ガード: title/detail に明白な credential パターン（`AKIA[0-9A-Z]{16}`、`ghp_[A-Za-z0-9]{36}`、`sk-[A-Za-z0-9]{20,}`、`-----BEGIN.*PRIVATE KEY` 等）を検出したら該当フィールドを `[REDACTED]` に置換して記録
- `ORGOS_ACTIVITY_DIR` 環境変数でストア位置を上書き可（テスト用）

### 4.2 `scripts/activity/journal.sh` (query / digest)

```
journal.sh today                     # 今日のダイジェスト (Markdown)
journal.sh --date 2026-06-10         # 指定日
journal.sh --days 7                  # 直近7日
journal.sh --repo OrgOS --type note  # フィルタ
journal.sh --format json|md|tsv
```

Markdown ダイジェスト構成:

```markdown
# OrgOS Journal — 2026-06-10
## サマリ: N リポジトリ / M イベント / セッション K 回
## 💭 考えたこと (decision/note/thought)
- HH:MM [repo] title
## ⚙️ 実行したこと
### repo-A
- HH:MM type title (T-XXX)
```

### 4.3 `scripts/activity/bridge-kernel-events.sh` (既存イベントの取り込み)

- カレントリポジトリの `.ai/events/events-*.jsonl` (orgos-event.v1) を走査し、未取込イベントを中央ストアへ変換追記
- 変換: `event_type→kernel`、`payload` 要約を title 化、`origin_event_id` に元 ID
- カーソル管理で冪等（再実行しても重複しない）
- SessionStart hook から best-effort 実行（存在しない/失敗でもセッションを止めない）

### 4.4 Hook 統合 (`.claude/settings.json`)

```json
"SessionStart": [... 既存 ...,
  {"type": "command", "command": "bash scripts/activity/log-event.sh --type session_start --title 'session start' --source hook --stdin-hook 2>/dev/null || true"},
  {"type": "command", "command": "bash scripts/activity/bridge-kernel-events.sh 2>/dev/null || true"}],
"Stop": [... 既存 ...,
  {"type": "command", "command": "bash scripts/activity/log-event.sh --type session_end --title 'session end' --source hook --stdin-hook 2>/dev/null || true"}]
```

### 4.5 `/org-journal` skill (`.claude/skills/org-journal/SKILL.md`)

- Owner が `/org-journal` または「今日何やったっけ」→ Manager が `journal.sh` を実行して整形提示
- skill 本文に **Manager 向け記録規約** を含める: 顕著な行動（タスク完了・重要判断・方針メモ）は
  `log-event.sh --type decision|note|task_done --title "..."` で記録すること（distributed clone でも同じ）

### 4.6 配布 (`.orgos-manifest.yaml`)

- `publish` に追加: `scripts/activity/log-event.sh`, `scripts/activity/journal.sh`, `scripts/activity/bridge-kernel-events.sh`, `.claude/skills/org-journal/SKILL.md`
- `core`（/org-import 上書き対象）にも scripts/activity を追加 → 全クローンが更新を受け取る

### 4.7 MCP サーバ (`scripts/activity/mcp-journal-server.py`) — Owner 要件 R6

中央ストアを **MCP ツールとしてどこからでも参照可能**にする（Claude Code の全プロジェクト / 対応クライアント）。

- **実装**: python3 標準ライブラリのみの stdio MCP サーバ（JSON-RPC 2.0、外部依存ゼロ）
- **提供ツール**:
  - `journal_get(date?, days?)` — 日次ダイジェスト（Markdown / JSON）
  - `activity_search(query?, repo?, type?, days?)` — イベント横断検索
  - `activity_log(type, title, detail?, task_id?)` — どこからでもメモ・思考を記録（書込も MCP 経由で可能に）
- **登録**: `scripts/activity/install-mcp.sh` が `claude mcp add --scope user orgos-journal ...` を実行
  → user スコープ登録なので**全リポジトリ・全プロジェクトから利用可能**（クローンごとの設定不要）
- ストアは常にローカル `~/.orgos/activity/` を読む（サーバはどのリポジトリから起動されても同じデータを見る）

### 4.8 Journal UI — orgos-dashboard への組込（Owner 承認: 案 A）

閲覧の主役は **既存 orgos-dashboard**（`~/Dev/Private/orgos-dashboard`、Next.js 15 + Tailwind 4）に追加する Journal 画面。
見た目の合意ベースは `outputs/2026-06-10/journal-ui-mock.html`（Owner 承認済みモック）。

- **API**: `src/app/api/journal/route.ts` — `GET /api/journal?date=YYYY-MM-DD | days=N [&repo=]`
  サーバ側で `~/.orgos/activity/events-*.jsonl` を読み、`{summary: {repos, events, sessions}, events: [...]}` を返す
- **画面**: `src/app/journal/page.tsx` — モック準拠:
  日付ナビ（◀ 日付 ▶ / 日・週切替）、サマリカード 4 枚、リポジトリフィルタチップ、
  左パネル「💭 考えたこと」（decision/note/thought 時系列）、右パネル「⚙️ 実行したこと」（リポジトリ別グループ）
- **導線**: トップページ（プロジェクト一覧）のヘッダに Journal タブを追加
- 表示はローカルタイムゾーン。既存コード規約（reader.ts / aggregator.ts のパターン）に従う
- 検証: `npm run build` 成功 + 実データでの表示確認

## 5. 非機能要件 / Definition of Done (quality_level: mvp)

| 軸 | レベル |
|---|---|
| functionality | happy path + 主要エラー（ストア書込不可、git 外、stdin なし） |
| error_handling | hook 経路は必ず exit 0、エラーは errors.log。CLI 経路は明示エラー |
| security | secret パターン redact。中央ストアに secret 実体を書かない。ストアは `~/.orgos`（リポジトリ外・git 管理外） |
| performance | 追記 O(1)。digest は対象月シャードのみ読む |
| observability | errors.log + journal.sh 自身が観測手段 |
| documentation | SKILL.md + 本設計書 |

## 6. やらないこと (out_of_scope)

- SQLite インデックス（イベント増加後の v2）/ Web UI 本体（orgos-dashboard 連携は v2。ただしスキーマと MCP の JSON 出力は dashboard が読める形に v1 から固定）
- 過去の RUN_LOG.md / DECISIONS.md の遡及取り込み（形式が不定）
- リモート同期（クラウド保存）— ローカル `~/.orgos` のみ。リモート参照は MCP で代替
- 既存 `~/.orgos/projects.yaml` の形式変更（dashboard フローの所有物）

## 7. テスト計画 (T-OS-483)

1. log-event: 基本追記 → JSONL 1 行・スキーマ準拠
2. log-event: `--stdin-hook` で session_id 抽出
3. log-event: secret パターン → REDACTED 置換
4. log-event: ストア書込不可でも exit 0
5. journal: 日付フィルタ・repo フィルタ・md/json 出力
6. bridge: orgos-event.v1 取り込み → 冪等（2 回実行で重複なし）
7. 並行追記: 2 プロセス同時 append → 行破損なし
8. `ORGOS_ACTIVITY_DIR` でテスト分離（実ストアを汚さない）
9. MCP サーバ: initialize → tools/list → tools/call (journal_get / activity_search / activity_log) の JSON-RPC ラウンドトリップが stdio で成功する
10. MCP サーバ: 不正リクエストでもクラッシュせず JSON-RPC エラーを返す
