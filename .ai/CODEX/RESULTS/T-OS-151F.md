# T-OS-151F Result

## 1. 変更ファイル一覧

- `.claude/schemas/user-profile.yaml`
- `.claude/rules/memory-lifecycle.md`
- `.ai/USER_PROFILE.example.yaml`
- `.ai/USER_PROFILE.yaml`
- `.claude/evals/manager-quality/report.py`
- `.pre-commit-config.yaml`

## 2. F1〜F7 対応表

| ID | 対応 | 備考 |
|---|---|---|
| F1 | DONE | `common_memory_metadata` を schema に追加し、facts / secrets / preferences に `source_ref` / `valid_from` / `expires_at` / `last_verified_at` を適用。`pii_level` は preferences では optional のまま維持。 |
| F2 | DONE | `transferability` enum (`none`, `project_to_domain`, `domain_to_global`, `explicit_only`) を schema に追加し、lifecycle の promote 条件へ反映。default は `none`。 |
| F3 | DONE | `report.py` を実データ判定へ更新。`repeated_question` 4 件は `USER_PROFILE.facts` の `past_qa` を参照、`decision_trace` 2 件は fact metadata 完備で判定。他カテゴリは mock 維持。README 追記は allowed paths 外のため未実施。 |
| F4 | DONE | `memory-lifecycle.md` に `pii_level` rubric を追加。迷ったら 1 段階上を選ぶ運用も明記。 |
| F5 | DONE | `past_qa_fact.value_ref` に `answer` / `answer_redacted` / `secret_ref` variant を追加し、`answer` は `pii_level: none|low` 限定ルールを追記。 |
| F6 | DONE | `normalize lint` / `promote lint` / `scope lint` を仕様として明文化。`scripts/memory/` 配下の lint 実装候補として記載。 |
| F7 | DONE | `.pre-commit-config.yaml` を新規追加。`gitleaks` を有効化し、`USER_PROFILE` 専用 hook は未実装 placeholder として comment で保持。 |

## 3. Manager Quality Eval 再実行結果

- 実行コマンド: `PYTHONDONTWRITEBYTECODE=1 bash .claude/evals/manager-quality/run.sh`
- 実行日: `2026-04-19`
- 結果: `cases=20`, `passed=6`, `failed=14`
- `repeated_question` 系: `4/4 pass`
- `decision_trace` 系: `2/2 pass`
- 他カテゴリは runtime wiring 未実装のため mock fail 継続

## 4. 残課題

- LOW 指摘 3 件は `T-OS-151G` へ切り出しで妥当
- graph memory 拡張余地
- 1000+ facts 時の大規模化 / index / 競合制御
- scope canonical naming rule
- `.claude/evals/manager-quality/README.md` の移行方針追記は work order 要求だが allowed paths 外のため未実施

## 5. 検証

- `ruby -e 'require "yaml"; ...'` で schema / example / local profile / pre-commit YAML の parse を確認
- `PYTHONDONTWRITEBYTECODE=1 bash .claude/evals/manager-quality/run.sh`
- `PYTHONDONTWRITEBYTECODE=1 python3 .claude/evals/manager-quality/report.py run --repo-root . --output-dir .ai/METRICS/manager-quality --json`

## 6. ステータス

- `DONE_WITH_CONCERNS`
