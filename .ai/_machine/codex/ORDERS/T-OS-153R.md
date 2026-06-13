# Work Order: T-OS-153R (Review)

## Task
- ID: T-OS-153R
- Title: T-OS-153 (Capability Preflight) 独立レビュー
- Role: reviewer
- Priority: P1

## Allowed Paths
- `.ai/CODEX/RESULTS/T-OS-153R.md` (結果記録用のみ)

## Context

T-OS-153 で実装された Capability Preflight (CAPABILITIES.yaml as tool manifest) を独立レビューする。
**実装者の自己報告を信用しない** (Pro 指摘の Iron Law)。独立検証が役割。

### レビュー対象ファイル (read-only)
- `.ai/CAPABILITIES.yaml` (scan.sh の初回実行結果)
- `.ai/CAPABILITIES.example.yaml`
- `.claude/schemas/capability.yaml`
- `.claude/rules/capability-preflight.md`
- `scripts/capabilities/scan.sh`
- `scripts/capabilities/probe/*.sh` (8 個)

### 参照ドキュメント
- `.ai/CODEX/ORDERS/T-OS-153.md` (元 Work Order)
- `.ai/CODEX/RESULTS/T-OS-153.md` (実装者の自己報告)
- `.ai/DESIGN/CHATGPT_PRO_REVIEW_2026-04-18.md` (Pro 指摘の SSOT)

## レビュー観点

### R1: Pro 指摘への対応
以下が実装されているか検証:
- auth_status, risk_level, supports_dry_run, owner_approval_required_for が全 capability に存在
- input_resolution_order が ["USER_PROFILE.facts", "ENV", "Owner"] の順で定義
- common_operations に再利用可能な操作パターン
- MCP 互換 (mcp_compat フィールド)

### R2: scan.sh の冪等性
- scan.sh を 2 回実行して結果が diff なしか実際に確認 (bash scripts/capabilities/scan.sh; diff <(cat CAPABILITIES.yaml) <(bash scripts/capabilities/scan.sh && cat CAPABILITIES.yaml))
- 変化があるべきフィールド (verified_at 等) の扱いが正しいか
- manual 編集部分を保持するマージロジックが機能するか

### R3: probe の graceful degradation
- 各 probe (cli-supabase.sh など) が CLI 未インストール時も失敗せずに JSON 出力するか
- auth_status の判定ロジックが正しいか (特に gh が expired と判定される実環境)
- 未知の CLI (cli-generic.sh) の扱い

### R4: Iron Law の厳格性
`capability-preflight.md` の Iron Law が:
- 本当に例外なし
- 「手順依頼する前に必ず CAPABILITIES を探索」が測定可能
- Red Flag (違反兆候) が列挙されている

### R5: MCP 互換性
- mcp_compat フィールドが実際に MCP Tools / Resources 仕様と互換
- 将来 MCP サーバー化する際のエクスポート経路が示されているか
- MCP 仕様 https://modelcontextprotocol.io/specification/2025-11-25 への参照

### R6: 検出の網羅性
scan 結果が 58 capability (cli=18, internal_skill=14, internal_agent=15, script=11):
- 重要な CLI が漏れていないか (特に stripe は unavailable だが、将来のため probe は用意されているか確認)
- internal_skill / internal_agent の列挙が正しいか (.claude/skills/, .claude/agents/ の全 md を網羅しているか)
- MCP 検出ロジックが ~/.claude.json / .mcp.json の両方を確認しているか

### R7: risk_level 判定の一貫性
- 同じ CLI でも操作により risk_level が変わるべきケースがある (supabase query = low, supabase db reset = critical)
- このような operation-level の risk 判定が schema に組み込まれているか
- owner_approval_required_for の列挙が網羅的か

### R8: 未解決リスクの発見
- auth_status=expired (gh) の扱い: 次 Tick で自動再認証を promptするか、Owner に通知するか
- CAPABILITIES.yaml が gitignored されているか (secret が混入する可能性があるため確認)
- scan.sh 実行時のネットワーク依存 (aws sts, supabase status 等が offline で失敗する場合の扱い)
- 複数 Owner が同じ repo を使う場合の機器依存性の扱い

## Instructions

1. R1〜R8 を順次独立検証
2. scan.sh を自分で実行して diff 確認 (R2 の冪等性テスト)
3. 各 probe を単独実行して JSON 出力を確認
4. 実装者の自己報告と独立事実が一致しているか確認
5. 重要度別に問題を分類
6. **重要**: ファイル編集禁止 (書き込みは `.ai/CODEX/RESULTS/T-OS-153R.md` のみ)

## Report

`.ai/CODEX/RESULTS/T-OS-153R.md` に T-OS-151R と同じフォーマットで記録:
- 総合判定 (◎/○/△/×)
- R1〜R8 観点別評価
- CRITICAL / HIGH / MEDIUM / LOW 問題リスト
- 修正タスク候補
- ステータス: APPROVED / APPROVED_WITH_MINOR_FIXES / CHANGES_REQUESTED / REJECTED

stdout 最終メッセージに総合判定と主要指摘のサマリーを含める。
