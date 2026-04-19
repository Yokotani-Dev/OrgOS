# Codex CLI 0.77 → 0.121 アップグレード差分

調査対象: `openai/codex` rust-v0.77.0 (2025-12-21) 〜 rust-v0.121.0 (2026-04-15)
現行ローカル版: `codex-cli 0.121.0`
作成日: 2026-04-18

---

## 1. サマリ

- **`-a/--ask-for-approval` の `on-failure` が DEPRECATED**（0.102.0）。非対話は `never`、対話は `on-request` を推奨。CONTROL.yaml の記述要更新。
- **`--full-auto` エイリアスが追加**（`-a on-request --sandbox workspace-write`）。OrgOS の委任パスで最短コマンドになる。
- **`codex exec` に `--json`, `--output-schema`, `--output-last-message`, `--ephemeral`, `--skip-git-repo-check` が整備**。Manager が結果をパースしやすくなった（JSONL ストリーム対応）。
- **`codex exec` 直下に `resume` と `review` サブコマンド**（非対話）。`codex exec resume <id>` / `codex exec resume --last` で前回セッションを CI 的に継続可。
- **プロジェクト階層 config 対応**（0.78 以降）: `/etc/codex/config.toml` → `~/.codex/config.toml` → `.codex/config.toml` のマージ。`project_root_markers` / `requirements.toml` / `AGENTS.md` が認識される。
- **`--remote wss://…` モード**（TUI を遠隔 app-server に接続）と、`codex exec-server`・`codex mcp`・`codex marketplace`・`codex features`・`codex debug` などのサブコマンドが追加。
- **sandbox モードが細分化**: `workspace-write` は維持されつつ、読み取り `ReadOnlyAccess`、Linux の bubblewrap 移行（0.114 でデフォルト）、Windows sandbox 昇格、network proxy/SOCKS5、「split filesystem / network」ポリシー、`requirements.toml` による企業ポリシー（`allowed_sandbox_modes`, `allowed_web_search_modes` 等）。
- **memories / plugins / skills / hooks が正式機能化**: `.ai/` 相当の永続メモリ、`codex marketplace add`（Git/ローカル/URL）、`.agents/skills` or `~/.agents/skills` 経由の Skill、`SessionStart` / `Stop` / `userpromptsubmit` / `PreToolUse` / `PostToolUse` のフック。
- **headless/device-auth の改善**: 非対話環境で自動的にデバイスコード認証に切替（0.81〜0.88）。`codex login --device-auth` で明示可能。CI で有用。
- **stdin パイプ対応**（0.118）: `codex exec` が `<prompt>` と stdin を同時に受理。OrgOS の Work Order 渡しで便利。
- **devcontainer 用セキュアプロファイル**（0.121）: bubblewrap 前提の Docker 内セキュア実行形態。

---

## 2. バージョン別ハイライト（OrgOS 関連のみ）

| ver | 日付 | OrgOS 関連ハイライト |
|-----|------|--------------------|
| 0.77 | 2025-12-21 | `requirements.toml` に `allowed_sandbox_modes` 追加。MCP OAuth が feature flag 不要に。 |
| 0.78 | 2026-01-06 | **プロジェクト階層 config** (`.codex/config.toml` + `project_root_markers` + `/etc/codex/config.toml`)。`ExecPolicyManager` 導入。 |
| 0.79 | 2026-01-07 | **`codex exec resume` 後にグローバル exec フラグを渡せる**ようになった (#8440)。analytics 設定追加。 |
| 0.80 | 2026-01-09 | `requirement/list`（requirements.toml 読み出し）。`/elevate-sandbox` 追加。`LD_LIBRARY_PATH` 継承問題を修正（パフォーマンス 10x+ 回帰解消）。 |
| 0.81 | 2026-01-14 | **API デフォルトモデルが `gpt-5.2-codex` に**。Linux sandbox が read-only bind mount 可。Windows で read-only 時に unsafe command のプロンプトが出るように。 |
| 0.85 | 2026-01-15 | **`codex resume --last` が現在の cwd を尊重**（`--all` で全件表示）。stdin の BOM/UTF-16 対応。 |
| 0.86 | 2026-01-16 | Skill メタデータが `SKILL.toml` で定義可能。 |
| 0.88 | 2026-01-21 | **device-code auth が standalone fallback に昇格**（headless 判定）。`codex exec resume --last` 整備。collaboration mode 導入。 |
| 0.89 | 2026-01-22 | **`/permissions` コマンド**（`/approvals` は互換）。layered config.toml を app-server が解決。TUI2 実験終了。 |
| 0.90 | 2026-01-25 | network sandbox proxy。**`--yolo` が git repo check をスキップ**。connectors phase 1。 |
| 0.92 | 2026-01-27 | `web_search` キャッシュがデフォルトに。multi-agent に max-depth ガード。 |
| 0.93 | 2026-01-31 | **SOCKS5 proxy** リスナー。**Plan mode** と `/plan` ショートカット。smart approvals がデフォルト。 |
| 0.94 | 2026-02-02 | **Plan mode デフォルト ON**。`.agents/skills` から skill 読込。 |
| 0.95 | 2026-02-04 | **shell ツールの並列実行**。**`CODEX_THREAD_ID` を exec に注入**。git コマンドの安全強化（`git add -p` 以外の書込操作を無承認で実行する抜け道を修正）。 |
| 0.96 | 2026-02-04 | `thread/compact` 非同期化。`unified_exec` が Windows 以外で有効化。 |
| 0.97 | 2026-02-05 | **`/debug-config`** で実効設定確認。`log_dir` 設定可（`-c` でも上書き可）。 |
| 0.98 | 2026-02-05 | **GPT-5.3-Codex 導入**。steer モードがデフォルト（実行中 Enter で即送信、Tab でキュー）。 |
| 0.99 | 2026-02-11 | **`/statusline` 設定**。ユーザ shell コマンドがターン中断しない。enterprise network constraints を requirements.toml で定義可。画像入力が GIF/WebP 対応。 |
| 0.100 | 2026-02-12 | experimental `js_repl` runtime。ReadOnlyAccess sandbox policy。windows sandbox 昇格。 |
| 0.102 | 2026-02-17 | **`approval_policy: on-failure` が DEPRECATED**。multi-agent の role をカスタマイズ可。`/debug-config` で無効パスを把握可。 |
| 0.103 | 2026-02-17 | `command_attribution` 設定（Co-Author 表記制御）。 |
| 0.104 | 2026-02-18 | `WS_PROXY`/`WSS_PROXY` 環境変数対応。 |
| 0.105 | 2026-02-25 | `/copy`, `/clear`, Ctrl-L。`spawn_agents_on_csv` で並列エージェント fan-out。approval の `Reject` ポリシー。 |
| 0.106 | 2026-02-26 | macOS/Linux 直接インストールスクリプト公開。`js_repl` が `/experimental` に昇格。 |
| 0.107 | 2026-03-02 | スレッドを sub-agent にフォーク可。`codex debug clear-memories`。MCP OAuth `oauth_resource` 対応。 |
| 0.110 | 2026-03-05 | **プラグインシステム**（skills / MCP / connectors を config or local marketplace から）。`/fast` モード。persist memory の workspace-scoped 化。Windows 直接インストーラー。 |
| 0.111 | 2026-03-05 | **Fast mode デフォルト ON**。 |
| 0.112 | 2026-03-08 | `@plugin` メンション。skill の permission profile を turn sandbox にマージ。 |
| 0.113 | 2026-03-10 | `request_permissions` ビルトインツール。plugin marketplace 充実、curated + `plugin/uninstall`。web search tool を完全設定可。 |
| 0.114 | 2026-03-11 | **experimental `code_mode`**。`SessionStart`/`Stop` hook エンジン。`GET /readyz` `/healthz` エンドポイント。bundled skills を無効化する config。 |
| 0.115 | 2026-03-16 | Smart Approvals の guardian subagent。app-server で fs RPC（file read/write/copy/watch）。`custom CA` login。 |
| 0.116 | 2026-03-19 | device-code ChatGPT onboarding。`userpromptsubmit` hook。プラグイン提案/インストール連携。 |
| 0.117 | 2026-03-26 | サブエージェントにパス形式アドレス (`/root/agent_a`)。`/title` 設定。app-server で `!` shell command 対応と fs watch。`tui_app_server` がデフォルト。 |
| 0.118 | 2026-03-31 | **`codex exec` が prompt + stdin の組合せをサポート**。Windows sandbox で proxy-only egress 強制。ChatGPT device-code を app-server から起動可能に。 |
| 0.119 | 2026-04-10 | realtime voice v2 (WebRTC)。`/resume` で ID/名前直接指定。`Ctrl+O` で直近 agent 応答コピー。MCP Apps / custom MCP の resource / elicitation / file upload。egress websocket transport、remote `--cd`、`codex exec-server`。 |
| 0.120 | 2026-04-11 | realtime V2 で背景エージェント進捗ストリーミング。`SessionStart` hook が `/clear` セッションを識別可。status line に thread title。 |
| 0.121 | 2026-04-15 | **`codex marketplace add`**（GitHub / Git URL / ローカル / `marketplace.json` URL からプラグイン marketplace 追加）。`Ctrl+R` 逆向き履歴検索。memory リセット/削除 UI。MCP Apps tool call、namespaced MCP registration、parallel MCP tool call。secure devcontainer profile。`danger-full-access` denylist-only mode は revert（0.119 で追加されたが 0.121 で撤去）。 |

（0.84, 0.87, 0.91, 0.101, 0.103 等の小リリースは OrgOS 影響なしのため省略）

---

## 3. 現行 CLI 仕様スナップショット

### `codex --help`（抜粋 / 0.121.0）

```
Commands:
  exec         Run Codex non-interactively [aliases: e]
  review       Run a code review non-interactively
  login        Manage login
  logout       Remove stored authentication credentials
  mcp          Manage external MCP servers for Codex
  marketplace  Manage plugin marketplaces for Codex
  mcp-server   Start Codex as an MCP server (stdio)
  app-server   [experimental] Run the app server or related tooling
  app          Launch the Codex desktop app (downloads the macOS installer if missing)
  completion   Generate shell completion scripts
  sandbox      Run commands within a Codex-provided sandbox
  debug        Debugging tools
  apply        Apply the latest diff produced by Codex agent as a `git apply` [aliases: a]
  resume       Resume a previous interactive session
  fork         Fork a previous interactive session
  cloud        [EXPERIMENTAL] Browse tasks from Codex Cloud and apply changes locally
  exec-server  [EXPERIMENTAL] Run the standalone exec-server service
  features     Inspect feature flags

Options:
  -c, --config <key=value>      Override config (dotted, TOML value)
      --enable <FEATURE>        Enable feature flag (repeatable)
      --disable <FEATURE>       Disable feature flag (repeatable)
      --remote <ADDR>           ws://host:port or wss://host:port (remote app server)
      --remote-auth-token-env <ENV_VAR>
  -i, --image <FILE>...
  -m, --model <MODEL>
      --oss                     Use local OSS provider (LM Studio / Ollama)
      --local-provider <lmstudio|ollama>
  -p, --profile <CONFIG_PROFILE>
  -s, --sandbox <read-only|workspace-write|danger-full-access>
  -a, --ask-for-approval <untrusted|on-failure|on-request|never>    # on-failure: DEPRECATED
      --full-auto                    # = -a on-request --sandbox workspace-write
      --dangerously-bypass-approvals-and-sandbox
  -C, --cd <DIR>
      --search                        Enable live web_search
      --add-dir <DIR>                 Additional writable roots
      --no-alt-screen
```

### `codex exec --help`（抜粋 / 0.121.0）

```
Commands:
  resume  Resume a previous session by id or --last
  review  Run a code review against the current repository

Options:
  -c, --config <key=value>
      --enable <FEATURE>            --disable <FEATURE>
  -i, --image <FILE>...             -m, --model <MODEL>
      --oss                         --local-provider <lmstudio|ollama>
  -s, --sandbox <...>               -p, --profile <CONFIG_PROFILE>
      --full-auto                   --dangerously-bypass-approvals-and-sandbox
  -C, --cd <DIR>                    --skip-git-repo-check
      --add-dir <DIR>               --ephemeral
      --output-schema <FILE>        JSON Schema for final response shape
      --color <always|never|auto>
      --json                        Print events as JSONL on stdout
  -o, --output-last-message <FILE>  Write last agent message to FILE
```

注: `codex exec` には `-a/--ask-for-approval` が **ない**。exec は非対話用途のため承認モード指定は `--full-auto` か `--dangerously-bypass-approvals-and-sandbox`、もしくは `-c approval_policy=never` で指定する（`codex resume` / 対話 `codex` では `-a` 使用可）。

### `codex resume --help`（抜粋 / 0.121.0）

```
Arguments:
  [SESSION_ID]   UUID or thread name
  [PROMPT]

Options:
      --last                        Continue most recent without picker
      --all                         Show all sessions (no cwd filter)
      --include-non-interactive     Include non-interactive sessions
      --remote <ADDR>               ws:// or wss://
  -m, --model  -p, --profile  -s, --sandbox  -a, --ask-for-approval
      --full-auto  --dangerously-bypass-approvals-and-sandbox
  -C, --cd <DIR>  --search  --add-dir <DIR>  --no-alt-screen
```

---

## 4. OrgOS への反映候補（アクション項目）

| # | 反映先ファイル | 変更内容 | 優先度 | 根拠 |
|---|----------------|----------|--------|------|
| A1 | `.ai/CONTROL.yaml` | `codex.approval` の選択肢コメントから `on-failure` を「DEPRECATED」と明記し、`on-request`（対話）/`never`（CI）を推奨に。デフォルト値が `on-request` の場合はそのままで OK、記載更新のみ。 | **H** | 0.102 |
| A2 | `.ai/CONTROL.yaml` / `CODEX_WORKER_GUIDE.md` | `codex exec` に `-a/--ask-for-approval` は **無い**ことを明記。非対話承認は `--full-auto` か `-c approval_policy=never`、もしくは `--dangerously-bypass-approvals-and-sandbox` で制御する旨。 | **H** | 現行 `codex exec --help` |
| A3 | `CODEX_WORKER_GUIDE.md` | **Work Order 投入パターンに `--json` / `--output-last-message` / `--output-schema` を使う**例を追記。Manager が結果を構造化して `.ai/CODEX/RESULTS/` に記録できる。 | **H** | 0.77→ |
| A4 | `CODEX_WORKER_GUIDE.md` | **`codex exec resume <id>` / `codex exec resume --last`** による継続実行の手順。長尺タスクを Tick 跨ぎで再開できる。 | **H** | 0.79, 0.85, 0.88 |
| A5 | `CODEX_WORKER_GUIDE.md` / `manager.md` | **stdin piping**: `echo "$PROMPT" \| codex exec --full-auto -` または `codex exec "initial" < /dev/stdin` で Work Order 本文を stdin 経由で渡せるようにする。 | **H** | 0.118 |
| A6 | `.ai/CONTROL.yaml` | `codex:` セクションに `model`（例: `gpt-5.2-codex` or `gpt-5.3-codex`）、`profile`、`config_overrides` を追記できる構造を用意。現行 memory に「`-m` でモデル指定しない」ルールがあるため、**Manager が `-c` で上書きする際は Codex の config.toml プロファイル側に書くのを優先**、のガイド追記。 | **H** | 0.81, 0.98 + user memory |
| A7 | `CODEX_WORKER_GUIDE.md` | **`--skip-git-repo-check`** を明示。OrgOS が git repo 外の scratch dir で codex を走らせる場面向け。 | M | 既存 / 0.78〜 |
| A8 | `CODEX_WORKER_GUIDE.md` | **`--ephemeral`** フラグ: セッションを rollout に永続化しない。実験的な試行や一過性のタスク向け。 | M | 既存 / 0.78〜 |
| A9 | `.claude/rules/project-flow.md` or 新規 | **階層 config** の存在を知らせる:`~/.codex/config.toml` → リポ直下 `.codex/config.toml` → `/etc/codex/config.toml` がマージされる。OrgOS 配下に `.codex/config.toml` を置いてプロジェクト固有設定を表現できる。 | M | 0.78 |
| A10 | `CODEX_WORKER_GUIDE.md` | **`AGENTS.md`** がプロジェクトルートマーカー兼指示書として Codex に認識される。OrgOS の `.claude/agents/` とは別物なので混同注意（OrgOS ルート `AGENTS.md` を用意するならそこに Codex 向け指示を書ける）。 | M | 0.81 |
| A11 | `.ai/CONTROL.yaml` | `codex.sandbox: "workspace-write"` のコメントに、**追加書き込みディレクトリは `--add-dir`** で渡せると追記。Work Order で工芸物を `outputs/` 等に書く運用と整合。 | M | 既存 |
| A12 | `CODEX_WORKER_GUIDE.md` | **`CODEX_THREAD_ID`** が exec 内環境変数として渡ることを明記。スクリプトがセッションを識別できる。OrgOS の RESULTS 紐付けに活用できる。 | M | 0.95 |
| A13 | `CODEX_WORKER_GUIDE.md` / `manager.md` | **Plan mode / `/plan`** が 0.94 からデフォルト有効。`codex exec` は非対話でも Plan が混ざる可能性があるため、**実装タスクは `-c plan_mode=false`（or features の disable）** を推奨、と注記。 | M | 0.93, 0.94 |
| A14 | `.ai/CONTROL.yaml` | `codex.fast_mode: true|false` の設定。0.111 から Fast mode がデフォルト ON、OrgOS の長尺タスクでは `-c fast_mode=false`（または `/fast off`）にしたいケースがある。 | M | 0.110, 0.111 |
| A15 | `.claude/rules/agent-coordination.md` | `codex-implementer` サブエージェントの起動規約に **`--full-auto` を標準**（現在の `sandbox=workspace-write, approval=on-request` と等価）と明記、冗長な個別フラグを削減。 | M | 0.77〜 |
| A16 | `CODEX_WORKER_GUIDE.md` | **`requirements.toml`** による企業ポリシー: `allowed_sandbox_modes`, `allowed_web_search_modes`, network constraints など。OrgOS 側で strict プロファイルが要る場合の入口として紹介。 | L | 0.77, 0.99 |
| A17 | 新規 or `CODEX_WORKER_GUIDE.md` | **`codex features list` / `--enable <F>` / `--disable <F>`** で実験機能を制御する手段を追記（Plan mode、steer、guardian、memories、plugins 等）。 | L | 0.89〜 |
| A18 | 新規 | **`codex marketplace add <src>`** で OrgOS 独自プラグイン（skills/MCP）を配布する可能性を将来検討。 | L | 0.121 |
| A19 | `CODEX_WORKER_GUIDE.md` | Linux で bubblewrap が無い場合のフォールバックおよび `/usr/bin/bwrap` 検出の挙動変更（0.114 でデフォルト化、0.116/117 で system bwrap 優先）。CI/devcontainer で注意。 | L | 0.114〜 |
| A20 | `CODEX_WORKER_GUIDE.md` | `codex mcp` サブコマンド体系（`mcp add/remove/login`）や `codex logout`、`codex sandbox` 直接実行の存在を一言メモ。 | L | 既存〜 |

---

## 5. 反映不要・保留項目

| 項目 | 理由 |
|------|------|
| TUI 配色 / syntax highlighting / `/theme` / voice transcription | OrgOS は非対話利用中心（Manager は Claude Code で動く）。TUI は Owner が直接触る場合のみ関係。 |
| Realtime voice（WebRTC v2）/ Realtime transcript | OrgOS のワークフローに音声入出力は組み込まれていない。 |
| `js_repl`, `code_mode` | experimental。OrgOS の実装委任パターンは既に `codex exec` で完結しており、再現性の観点からも experimental には乗らない方がよい。 |
| `cloud`, `app-server` / `exec-server` / `--remote wss://` | 単一マシン + Claude Code の Manager で完結しており、現時点で app-server 経由の分散は不要。将来 Owner が複数端末で運用する場合に再検討。 |
| Realtime / multi-agent v2 (spawn_agent / wait_agent) | OrgOS 側でエージェント協調を既に Manager が握っているため、Codex 内の multi-agent は二重管理を招く。使わない方針を維持。 |
| Personality / collaboration mode | UX 向け設定。OrgOS の出力は Work Order 経由で機械的に扱うため、過度な人格調整は避ける。 |
| Windows TUI 固有の修正（UTF-8, paste-burst, WSL 等） | Owner のプラットフォームは macOS。必要時のみ参照。 |
| Hooks（SessionStart/Stop/userpromptsubmit/PreToolUse/PostToolUse） | 有用だが、OrgOS 側 Tick フローと重複するため現状は採用保留。将来、Codex 側でのみ有効なフック（例: 禁則パス保護の強化）があれば個別採用を検討。 |
| guardian subagent（Smart Approvals） | OrgOS には既に org-reviewer / org-security-reviewer があり重複。 |

---

## 6. 検証コマンド

```bash
# バージョン・サブコマンド確認
/opt/homebrew/bin/codex --version
/opt/homebrew/bin/codex --help
/opt/homebrew/bin/codex exec --help
/opt/homebrew/bin/codex exec resume --help
/opt/homebrew/bin/codex resume --help
/opt/homebrew/bin/codex features list

# 現在の実効設定の確認（--remote/対話なし環境では TUI が起動するため注意）
# → 対話 TUI 内で /debug-config を実行するのが確実

# 最小動作確認: 非対話で echo して終了
/opt/homebrew/bin/codex exec --full-auto --skip-git-repo-check \
  --output-last-message /tmp/codex_out.txt \
  "Reply with the single word OK"
cat /tmp/codex_out.txt

# JSONL ストリームで結果を構造化
/opt/homebrew/bin/codex exec --full-auto --json --skip-git-repo-check \
  "echo hello from codex" | tee /tmp/codex_events.jsonl

# 前回セッション再開（--last）
/opt/homebrew/bin/codex exec resume --last "追加指示"

# stdin pipe での Work Order 投入
cat .ai/CODEX/ORDERS/T-123.md | /opt/homebrew/bin/codex exec --full-auto -

# 一過性セッション（rollout に残さない）
/opt/homebrew/bin/codex exec --full-auto --ephemeral "探索的なクエリ"

# 環境固有: --add-dir で追加書込ルートを指定
/opt/homebrew/bin/codex exec --full-auto --add-dir outputs "..."

# 階層 config 確認 (リポジトリ直下に置ける)
ls -la .codex/config.toml ~/.codex/config.toml /etc/codex/config.toml 2>/dev/null

# feature flags 操作例
/opt/homebrew/bin/codex --disable plan_mode exec --full-auto "..."
/opt/homebrew/bin/codex -c 'plan_mode=false' exec --full-auto "..."
```

---

## 付録: 主要な破壊的変更の注意事項

- **`-a on-failure` は DEPRECATED（0.102）**: 既存スクリプトがあるなら `on-request`（対話）か `never`（非対話 CI）へ移行。
- **`codex exec` には `-a` が無い**（昔からの仕様だが、対話 `codex` / `codex resume` にはある点が混同の元）。非対話で承認を制御したい場合は `-c approval_policy=never` を使う。
- **`-m` でモデルを指定しない**という Owner のメモリ（feedback_codex_model.md）に従い、モデルは config.toml のデフォルトを尊重する。本レポートの反映案でも「A6」で強調。
- **Plan mode / Fast mode がデフォルト ON**（0.94, 0.111）。非対話の OrgOS 実装タスクでは期待と乖離する可能性があるため、必要なら `--disable plan_mode` / `-c fast_mode=false` を明示。
- **Linux sandbox のデフォルトが bubblewrap**（0.114）。未インストール環境ではフォールバックするがログが出る。devcontainer/CI で `bwrap` を用意しておくと安定。
