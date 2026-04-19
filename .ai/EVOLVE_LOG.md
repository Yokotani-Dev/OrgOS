# EVOLVE LOG

> org-evolve の実行履歴。自動生成・自動追記。

---

## EVOLVE-001: patterns.md 重複コンテンツ除去 (2026-03-30)

| 項目 | 値 |
|------|-----|
| カテゴリ | deduplicate |
| 対象ファイル | .claude/rules/patterns.md |
| メトリクス（before） | 430行、38重複ペア |
| メトリクス（after） | 28行、30重複ペア |
| 結果 | KEEP |
| コミット | 7d175e7 |
| Eval | pass (7/7, warn 1) |

### 詳細
patterns.md（rules = 常時コンテキスト展開）に含まれていたコード例 ~400行を、
スキルファイルへの参照インデックスに置換。コンテキスト消費を大幅削減。
重複ペア数は 38 → 30 に改善（patterns.md が関与していた8ペアが解消）。

## EVOLVE-002: daily-health-check (2026-04-19)

| 項目 | 値 |
|------|-----|
| カテゴリ | daily-health |
| 対象ファイル | .claude/evals/manager-quality/daily-check.sh, scripts/evolve/daily-health-check.sh |
| メトリクス（before） | recent regressions: 0 |
| メトリクス（after） | manager quality: 20/20 pass |
| 結果 | KEEP |
| コミット | n/a |
| Eval | pass |
| 出典 | internal |
| run_id | `daily-health-2026-04-19` |

### 学習トレース
- 改善: repeated_question_rate, context_miss_rate, unnecessary_owner_question_rate, capability_reuse_rate, owner_delegation_burden, decision_trace_completeness
- 退行: none
- 学習内容: target_met metrics は daily baseline として維持対象; capability scan を先に実行すると reuse judge の前提が揃う
- 次の改善候補: 前日との差分学習を org-evolve external scan 入力へ供給
