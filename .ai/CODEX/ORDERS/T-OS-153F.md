# Work Order: T-OS-153F (Fix from T-OS-153R review)

## Task
- ID: T-OS-153F
- Title: T-OS-153 Capability Preflight レビュー指摘の修正 (HIGH + MEDIUM)
- Role: implementer
- Priority: P1

## Allowed Paths
- `.claude/schemas/capability.yaml` (編集)
- `scripts/capabilities/scan.sh` (編集)
- `scripts/capabilities/probe/*.sh` (編集)
- `.claude/rules/capability-preflight.md` (編集)
- `.gitignore` (編集)
- `.ai/CAPABILITIES.yaml` (再生成)
- `.ai/CAPABILITIES.example.yaml` (更新)
- `.ai/CODEX/RESULTS/T-OS-153F.md` (結果記録)

## Dependencies
- T-OS-153: done
- T-OS-153R: CHANGES_REQUESTED

## Context

T-OS-153R (Capability Preflight 独立レビュー) で △ 判定。
HIGH 3 件 + MEDIUM 4 件を修正する。LOW 2 件は次 phase で対応。
レビュー原文: `.ai/CODEX/RESULTS/T-OS-153R.md`

## Acceptance Criteria

### F1 [HIGH]: common_operations の merge 保持
問題: `scripts/capabilities/scan.sh:426-458` が `common_operations` を generated 値で全面上書きし、手動補完が消える。
修正: 
- scan.sh で `common_operations` を id (operation name) ベースで merge
- 手動追加された operation (scan で生成されていないもの) は保持
- 手動編集フィールドを検出し保持する戦略を実装 (notes フィールドと同様の方針)

### F2 [HIGH]: operation-level risk_level
問題: `common_operations` の各 operation に `risk_level`, `supports_dry_run`, `owner_approval_required_for` がなく、同一 CLI 内で read vs destructive を区別できない。
修正:
- `.claude/schemas/capability.yaml` の `common_operations[*]` schema に以下を追加:
  - `risk_level: enum[low, medium, high, critical]` (必須、デフォルト capability 直下の risk_level を継承)
  - `supports_dry_run: bool`
  - `owner_approval_required_for: list[string]`
- scan.sh で supabase の `get_project_api_keys` = low, `db_reset` = critical のように operation 別 risk を生成
- example.yaml を同期

### F3 [HIGH]: CAPABILITIES.yaml を gitignore
問題: `.ai/CAPABILITIES.yaml` は gitignore されておらず auth 状態や将来の手動補完値が commit される。
修正:
- `.gitignore` に `.ai/CAPABILITIES.yaml` を追加
- `.ai/CAPABILITIES.example.yaml` は commit 対象として維持
- README or capability-preflight.md に commit-safe 運用を追記

### F4 [MEDIUM]: input_resolution_order のデフォルト
問題: 43/46 operation で `input_resolution_order` が空。
修正:
- scan.sh で生成時に user-facing/reusable operation に `input_resolution_order: [USER_PROFILE.facts, ENV, Owner]` をデフォルト設定
- 既存 manifest に反映 (再生成)

### F5 [MEDIUM]: generic probe の単独実行対応
問題: `cli-generic.sh` は引数なしで usage + exit 1。
修正:
- 引数なし時も `{"status":"unknown", "error": "usage: cli-generic.sh <name>"}` の JSON を返す
- exit code 0 に変更 (graceful degradation)

### F6 [MEDIUM]: MCP 検出対象の拡張
問題: `~/.config/claude-code/mcp.json` + repo `.claude.json` のみ。
修正: scan.sh に以下を追加:
- `~/.claude.json`
- `.mcp.json` (repo root)
- 検出したものは `kind: mcp` として manifest に登録

### F7 [MEDIUM]: offline / network failure の区別
問題: vercel/aws probe が network error と auth failure を `unknown` に吸収。
修正:
- probe スクリプトで network error (ENOTFOUND, timeout 等) を検出
- 検出時: `status: degraded`, `auth_status: probe_error`, `error_detail: "network_error"` を返す
- auth failure: 従来通り `auth_status: expired` or `unverified`

## Instructions

1. レビュー原文 `.ai/CODEX/RESULTS/T-OS-153R.md` を精読
2. F1〜F7 を順次実装 (最小 diff)
3. 修正後に scan.sh を 2 回実行し、冪等性 + merge 保持を確認
4. 独立 probe 実行で JSON が正しく返るか確認
5. 再生成した `.ai/CAPABILITIES.yaml` で自己検証
6. **重要**: `.ai/DECISIONS.md`, `.ai/TASKS.yaml` 編集禁止

### 設計方針
- 既存 manifest の手動補完値を保護
- schema の後方互換 (新フィールドは optional または default 付き)
- probe は全て graceful (失敗時も JSON を返す)

## Reference (必読)
- `.ai/CODEX/RESULTS/T-OS-153R.md` - レビュー指摘原文
- 既存: `.claude/schemas/capability.yaml`, `scripts/capabilities/scan.sh`, `scripts/capabilities/probe/*.sh`

## Report

`.ai/CODEX/RESULTS/T-OS-153F.md` + stdout:
1. 変更ファイル一覧
2. F1〜F7 対応表
3. scan.sh 冪等性確認結果 (before/after diff)
4. CAPABILITIES.yaml 再生成後の件数変化
5. ステータス: DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED
