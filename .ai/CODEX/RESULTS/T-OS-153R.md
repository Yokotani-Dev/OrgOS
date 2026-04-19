# T-OS-153R Review Report

## 総合判定
- △ (要修正)

## 観点別評価
### R1: Pro 指摘対応
- 判定: △
- 確認内容:
  - 全 58 capability に `auth_status` / `risk_level` / `supports_dry_run` / `owner_approval_required_for` / `mcp_compat` は存在する。manifest の件数も `cli=18 / internal_skill=14 / internal_agent=15 / script=11` で自己報告と一致した（`.ai/CAPABILITIES.yaml`, `python3` 集計結果）。
  - `cli_supabase` は Pro 指摘どおり `input_resolution_order: [USER_PROFILE.facts, ENV, Owner]` を持つ（`.ai/CAPABILITIES.yaml:340-365`）。
- 問題点:
  - `common_operations` 46 件のうち 43 件で `input_resolution_order` が空。さらに `cli_codex` と `cli_gh` は `Task -> Owner` で、レビュー指示の `USER_PROFILE.facts -> ENV -> Owner` に揃っていない（`.ai/CAPABILITIES.yaml:63-72`, `.ai/CAPABILITIES.yaml:160-169`, `.ai/CAPABILITIES.yaml:20-25`, `.ai/CAPABILITIES.yaml:329-334`, `scripts/capabilities/scan.sh:172-225`, `scripts/capabilities/scan.sh:327-334`, `scripts/capabilities/scan.sh:365-372`, `scripts/capabilities/scan.sh:405-412`）。
  - `mcp_compat` は全件にあるが、実体は `resource_type` と簡素な `tool_schema` だけで、MCP Tools / Resources への export 手順や capability から server 化する経路は文書化されていない（`.claude/schemas/capability.yaml:57-68`, `scripts/capabilities/scan.sh:229-245`, `scripts/capabilities/scan.sh:336-339`）。

### R2: scan.sh の冪等性
- 判定: △
- 確認内容:
  - `bash scripts/capabilities/scan.sh` の再実行後、manifest 全文比較は `NO_DIFF` で、同一状態での再走査は安定していた。
  - `verified_at` は `kind/command/path/version/status/auth_status` が変化しない限り保持する分岐がある（`scripts/capabilities/scan.sh:435-458`）。
- 問題点:
  - 手動補完保持は部分的。`/tmp` に退避した manifest で `cli_gh.notes` と手動 `common_operations` を追加して scan を再実行したところ、`notes` は残った一方で手動追加した operation は消えた。`common_operations` を generated 値で全面上書きしているため、ルールの「手動補完値は尊重」に反する（`scripts/capabilities/scan.sh:426-434`, `scripts/capabilities/scan.sh:445-458`）。
  - 実装者報告の baseline と独立再実行結果が一致しない。報告では `node=v25.2.1`, `npm=11.6.2`, path は `/opt/homebrew/bin` だったが、独立再実行では `node=v22.18.0`, `npm=10.9.3`, path は `/usr/local/bin` になった。PATH 依存で baseline がぶれる（`.ai/CODEX/RESULTS/T-OS-153.md`, `.ai/CAPABILITIES.yaml:215-241`）。

### R3: probe の graceful degradation
- 判定: △
- 確認内容:
  - 専用 probe は CLI 未導入でも JSON を返す。`cli_stripe.sh` は未導入環境で `{"status":"unavailable","path":null}` を返した。
  - `cli_gh.sh` は実環境で `expired` を正しく再現した。`gh auth status` の生出力も token invalid を示した。
  - `cli_supabase.sh` は実環境で `unverified` を正しく再現した。`supabase projects list` の生出力も access token 不在を示した。
- 問題点:
  - `cli-generic.sh` は引数なし単独実行で usage を出して exit 1 になり、「単独実行でも失敗せず JSON を出力する」という観点では外れている（`scripts/capabilities/probe/cli-generic.sh:19-23`）。
  - オフライン時の扱いが弱い。`vercel whoami` は `ENOTFOUND api.vercel.com`、`aws sts get-caller-identity` は endpoint 接続失敗だったが、probe はどちらも `auth_status=unknown` にとどまり `degraded` や network error を表現できない（`scripts/capabilities/probe/cli-vercel.sh:24-32`, `scripts/capabilities/probe/cli-aws.sh:24-34`）。

### R4: Iron Law の厳格性
- 判定: ○
- 確認内容:
  - `例外なし` は明記されており、Owner に GUI/手動作業を依頼する前に `CAPABILITIES.yaml` を必ず確認するという中核要件は満たしている（`.claude/rules/capability-preflight.md:5-13`）。
  - Red Flag も具体的に列挙されている（`.claude/rules/capability-preflight.md:23-28`）。
- 問題点:
  - 「本当に探索したか」の機械的な測定方法は未定義。scan 実行ログや capability lookup trace までは要求されておらず、測定可能性は弱い（`.claude/rules/capability-preflight.md:35-40`）。

### R5: MCP 互換性
- 判定: △
- 確認内容:
  - schema には MCP 仕様 URL が記載されている（`.claude/schemas/capability.yaml:7-9`）。
  - 各 capability に `mcp_compat` は付与される（`.claude/schemas/capability.yaml:57-68`, `scripts/capabilities/scan.sh:254-273`）。
- 問題点:
  - MCP 検出は `~/.config/claude-code/mcp.json` と repo の `.claude.json` のみで、レビュー指示にある `~/.claude.json` / `.mcp.json` は見ていない（`scripts/capabilities/scan.sh:284-298`）。
  - 現 manifest に `kind: mcp` は 0 件で、`mcp_compat` が実際の server/resource export と整合するかは未検証のまま（`.ai/CAPABILITIES.yaml` 集計結果）。

### R6: 検出の網羅性
- 判定: △
- 確認内容:
  - capability 件数は 58 で、自己報告の `cli=18 / internal_skill=14 / internal_agent=15 / script=11` と一致した。
  - `scripts/capabilities/probe/` には 8 本あり、`stripe` の専用 probe も存在する（`scripts/capabilities/probe/cli-stripe.sh`）。
  - `.claude/skills/*.md` は 14 件、`.claude/agents/*.md` は 15 件で、manifest への列挙数と一致した。
- 問題点:
  - MCP 検出元が不足しているため、網羅性は完全ではない（`scripts/capabilities/scan.sh:284-298`）。
  - scripts 検出は `scripts/` 配下の全ファイルを一律 capability 化しており、将来バイナリや補助ファイルが入った場合のノイズ混入に弱い（`scripts/capabilities/scan.sh:380-417`）。

### R7: risk_level 判定の一貫性
- 判定: ×
- 確認内容:
  - capability 単位の `risk_level` と `owner_approval_required_for` はある（`.claude/schemas/capability.yaml:36-43`, `scripts/capabilities/scan.sh:79-170`）。
- 問題点:
  - Pro 指摘の「同一 CLI でも operation ごとに risk が変わる」を表現できない。schema も manifest も risk を capability 直下に 1 つしか持てず、`common_operations` の各 operation に risk / approval / dry-run を持たせる構造がない（`.claude/schemas/capability.yaml:36-55`, `scripts/capabilities/scan.sh:172-225`）。
  - そのため `cli_supabase` は capability 全体で `high` だが、`get_project_api_keys` のような read 系と `db reset` のような破壊系を分離評価できない（`.ai/CAPABILITIES.yaml:349-365`）。

### R8: 未解決リスクの発見
- 判定: △
- 確認内容:
  - `gh` の expired / `supabase` の unverified は独立実測で再現した。manifest の auth 状態自体は現実に近い。
- 問題点:
  - `auth_status=expired` や `unverified` を次 Tick でどう扱うかの自動運用がない。manifest に状態はあるが、Owner 通知や再認証促進の流れは未定義（`.claude/rules/capability-preflight.md:11-13`）。
  - `.ai/CAPABILITIES.yaml` は gitignore されていない。`.gitignore` は `.ai/USER_PROFILE.yaml` のみを守っており、manifest への secret 混入リスクを放置している（`.gitignore:1-9`）。
  - ネットワーク断時の probe 挙動が `unknown` に吸収され、offline と auth failure を区別できない（`scripts/capabilities/probe/cli-vercel.sh:24-32`, `scripts/capabilities/probe/cli-aws.sh:24-34`）。
  - baseline はローカル PATH とインストール位置に依存するため、複数 Owner / 複数端末で同じ repo を共有した場合に manifest 差分が発生しやすい（`.ai/CODEX/RESULTS/T-OS-153.md`, `.ai/CAPABILITIES.yaml:215-241`）。

## 発見した問題 (重要度別)
### CRITICAL
- なし

### HIGH
- `scripts/capabilities/scan.sh:426-458` - 手動補完保持が不完全で、既存 manifest の `common_operations` を generated 値で全面上書きする。独立検証でも手動追加 operation が再 scan で消えた - `common_operations` と `owner_approval_required_for` も merge 戦略を持たせ、手動追加を保持する。
- `.claude/schemas/capability.yaml:36-55` - operation-level risk/approval/dry-run を表現できず、Pro 指摘の「同一 CLI 内で操作ごとに risk が違う」を実装できていない - `common_operations[*]` に `risk_level`, `supports_dry_run`, `owner_approval_required_for` を持たせる。
- `.gitignore:1-9` - `.ai/CAPABILITIES.yaml` が gitignore されておらず、認証状態や将来の手動補完値が誤ってコミットされうる - `.ai/CAPABILITIES.yaml` を ignore し、commit-safe な `.ai/CAPABILITIES.example.yaml` のみ追跡対象にする。

### MEDIUM
- `.ai/CAPABILITIES.yaml:20-25`, `.ai/CAPABILITIES.yaml:63-72`, `.ai/CAPABILITIES.yaml:160-169`, `.ai/CAPABILITIES.yaml:329-334`, `scripts/capabilities/scan.sh:172-225`, `scripts/capabilities/scan.sh:327-334`, `scripts/capabilities/scan.sh:365-372`, `scripts/capabilities/scan.sh:405-412` - `input_resolution_order` が 43/46 operation で空、残り 2 件も要求順序と不一致 - 少なくとも user-facing / reusable operation では `USER_PROFILE.facts -> ENV -> Owner` を既定化する。
- `scripts/capabilities/probe/cli-generic.sh:19-23` - generic probe は単独実行だと JSON を返さず exit 1 - 引数欠落時も `status=unknown` の JSON を返すか、scan 専用であることを明記する。
- `scripts/capabilities/scan.sh:284-298` - MCP 検出が `~/.config/claude-code/mcp.json` と repo `.claude.json` のみで、`~/.claude.json` / `.mcp.json` を見ていない - review 指示に合わせて検索対象を拡張する。
- `scripts/capabilities/probe/cli-vercel.sh:24-32`, `scripts/capabilities/probe/cli-aws.sh:24-34` - offline/network failure と auth failure を区別できず `unknown` に落ちる - `status=degraded` か `probe_error` を追加して運用判断可能にする。

### LOW
- `.claude/rules/capability-preflight.md:35-40` - Iron Law 違反の機械検出方法が未定義 - trace/log の必須項目を追加する。
- `.ai/CODEX/RESULTS/T-OS-153.md` と `.ai/CAPABILITIES.yaml:215-241` - 実装者自己報告の node/npm baseline が独立再実行結果と一致しない - PATH 依存を前提とした注記か、実行シェルの固定を追加する。

## 修正タスク候補
- `T-OS-153 FIX-001`: `common_operations` の merge 保持ロジックを追加し、手動補完を再 scan で消さない
- `T-OS-153 FIX-002`: operation-level `risk_level` / `supports_dry_run` / `owner_approval_required_for` を schema と manifest に追加
- `T-OS-153 FIX-003`: `input_resolution_order` の既定順序を整理し、空配列を解消
- `T-OS-153 FIX-004`: MCP 検出対象を `~/.claude.json` / `.mcp.json` まで広げ、export 経路を設計メモ化
- `T-OS-153 FIX-005`: offline/network failure を `degraded` などで表現し、auth failure と分離
- `T-OS-153 FIX-006`: `.ai/CAPABILITIES.yaml` を gitignore し、manifest の commit-safe 運用を固定

## 検証コマンド
- `bash scripts/capabilities/scan.sh`
- `before=$(cat .ai/CAPABILITIES.yaml); bash scripts/capabilities/scan.sh >/tmp/t-os-153r-scan.out; after=$(cat .ai/CAPABILITIES.yaml); [ "$before" = "$after" ] && echo NO_DIFF`
- `for f in scripts/capabilities/probe/*.sh; do bash "$f"; done`
- `bash scripts/capabilities/probe/cli-generic.sh jq`
- `bash scripts/capabilities/probe/cli-generic.sh stripe`
- `gh auth status`
- `supabase projects list`
- `vercel whoami`
- `aws sts get-caller-identity`

## ステータス
- CHANGES_REQUESTED
