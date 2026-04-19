# T-OS-153F

## 1. 変更ファイル一覧

- `.claude/schemas/capability.yaml`
- `scripts/capabilities/scan.sh`
- `scripts/capabilities/probe/cli-generic.sh`
- `scripts/capabilities/probe/cli-aws.sh`
- `scripts/capabilities/probe/cli-vercel.sh`
- `.claude/rules/capability-preflight.md`
- `.gitignore`
- `.ai/CAPABILITIES.yaml`
- `.ai/CAPABILITIES.example.yaml`
- `.ai/CODEX/RESULTS/T-OS-153F.md`

## 2. F1〜F7 対応表

| ID | 対応 | 結果 |
| --- | --- | --- |
| F1 | `scan.sh` で `common_operations` を `name` ベース merge に変更。generated にない manual operation を保持し、`notes` のような manual field も保持 | DONE |
| F2 | `common_operations[*]` に `risk_level` / `supports_dry_run` / `owner_approval_required_for` を追加。`cli_supabase.get_project_api_keys=low`、`cli_supabase.db_reset=critical` を生成 | DONE |
| F3 | `.ai/CAPABILITIES.yaml` を `.gitignore` へ追加。`capability-preflight.md` に commit-safe 運用を追記 | DONE |
| F4 | generated operation に `input_resolution_order: [USER_PROFILE.facts, ENV, Owner]` を既定付与し、再生成後の空配列を解消 | DONE |
| F5 | `cli-generic.sh` を引数なしでも JSON + exit 0 で返すよう修正 | DONE |
| F6 | MCP 検出対象を `~/.config/claude-code/mcp.json` / `~/.claude.json` / `.claude.json` / `.mcp.json` に拡張 | DONE |
| F7 | `cli-aws.sh` / `cli-vercel.sh` に network failure 判定を追加し、`status=degraded` + `auth_status=probe_error` + `error_detail=network_error` を返せるよう修正 | DONE |

## 3. scan.sh 冪等性確認結果

- 1回目再生成: `.ai/CAPABILITIES.yaml` 更新
- 2回目再生成: `NO_DIFF`
- temporary manifest で manual merge も確認
- `cli_gh.common_operations.view_pr.notes = "manual note preserved"` は保持
- 手動追加した `manual_only_operation` は再 scan 後も保持
- 同 temporary manifest 上で `view_pr.input_resolution_order` は `[USER_PROFILE.facts, ENV, Owner]` に正規化

## 4. CAPABILITIES.yaml 再生成後の件数変化

- before: 58
- after: 58
- kinds: `cli=18 / internal_skill=14 / internal_agent=15 / script=11 / mcp=0`
- `common_operations` の `input_resolution_order` 空件数: `0`
- `cli_supabase` operation risk:
  - `get_project_api_keys = low`
  - `db_reset = critical`

## 5. 検証コマンド

- `bash -n scripts/capabilities/scan.sh scripts/capabilities/probe/cli-generic.sh scripts/capabilities/probe/cli-aws.sh scripts/capabilities/probe/cli-vercel.sh`
- `bash scripts/capabilities/scan.sh`
- `bash scripts/capabilities/scan.sh` (再実行、`NO_DIFF`)
- temporary manifest を使った manual merge 保持確認
- `bash scripts/capabilities/probe/cli-generic.sh`
- `bash scripts/capabilities/probe/cli-aws.sh`
- `bash scripts/capabilities/probe/cli-vercel.sh`

## 6. 補足

- 現環境では `cli-aws.sh` が `degraded / probe_error / network_error` を返すことを確認
- 現環境の `cli-vercel.sh` は `available / unknown` で、network error ケース自体は未再現。ただし判定ロジックは追加済み

## 7. ステータス

- DONE
