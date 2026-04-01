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
