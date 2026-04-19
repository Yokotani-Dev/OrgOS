# Capability Preflight

> Owner に技術的な作業を依頼する前に、必ず CAPABILITIES を探索する。

## Iron Law

> Manager は Owner に GUI 手順や手動作業を依頼する前に、必ず `CAPABILITIES.yaml` を確認する。例外なし。

1. 依頼を `cli` / `api` / `mcp` / `script` / `internal` に分類する
2. `.ai/CAPABILITIES.yaml` から該当 capability を検索する
3. `status=available` かつ `auth_status=verified|not_required` なら自動実行する
4. `status=available` だが `auth_status=unverified|expired|unknown` なら、Owner には認証確認だけを依頼する
5. `auth_status=probe_error` と `error_detail=network_error` は認証切れではなくネットワーク劣化として扱う
6. 該当 capability がない場合のみ、GUI 手順や手動作業を依頼する

## Decision Order

1. 既存 `common_operations` があるか確認する
2. `input_resolution_order` に従って必要入力を解決する
3. `risk_level` と `owner_approval_required_for` を確認する
4. dry-run が可能なら先に dry-run を試す
5. 実行後は必要に応じて capability を再 scan する

## Red Flags

- Owner に「Supabase ダッシュボードで...」と依頼する前に `CAPABILITIES.yaml` を確認していない
- 同じ `which <tool>` を毎回手動で実行している
- `common_operations` を無視して ad-hoc コマンドを組み立てている
- `risk_level=high` 以上なのに `owner_approval_required_for` を見ていない

## Relationship To Existing Rules

- このルールは `.claude/rules/owner-task-minimization.md` を強制化する Iron Law である
- 「CLI/API で代行できる作業を手動でやらせない」を、manifest-first の運用に変換する

## Operating Procedure

- 毎 Tick 開始時に `scripts/capabilities/scan.sh` を実行する
- `scan.sh` は冪等でなければならない
- 既存 manifest の手動補完値は尊重しつつ、新規発見と最新 probe 結果を差分更新する
- `.ai/CAPABILITIES.yaml` はローカル再生成物として扱い、commit しない。共有サンプルは `.ai/CAPABILITIES.example.yaml` を更新する
- `risk_level=high` 以上の操作では必ず `owner_approval_required_for` を参照する

## Examples

### Good

- `gh` が `available + verified` なら PR/Issue 操作は `gh` を再利用する
- `supabase` が `available + unverified` なら、Owner にはログイン確認だけ依頼する
- `filesystem` MCP が登録済みなら、GUI ではなく MCP/CLI ルートを優先する

### Bad

- capability 未確認で GUI 手順を即座に案内する
- manifest を無視して毎回ゼロから手段探索する
- destructive operation の承認条件を見ずに実行する
