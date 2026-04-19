# Work Order: T-OS-154F (Fix from T-OS-154R review)

## Task
- ID: T-OS-154F
- Title: T-OS-154 Request Intake Loop レビュー指摘修正 (HIGH 3 件)
- Role: implementer
- Priority: P0

## Allowed Paths
- `.claude/rules/request-intake-loop.md` (T-OS-154 で新規作成した成果物を改良、編集可)
- `.ai/CODEX/RESULTS/T-OS-154F.md`

## Note on Editing Policy
`request-intake-loop.md` は T-OS-154 (前工程) で新規作成されたファイル。
**既存 OS 中核ファイル (CLAUDE.md, manager.md) ではないため編集可能**。
AGENTS.md の「.claude/** 編集禁止」は OS 中核ファイル保護が趣旨と解釈。

## Dependencies
- T-OS-154: done
- T-OS-154R: CHANGES_REQUESTED

## Context

T-OS-154R で △ 判定。HIGH 3 件を修正する。
レビュー原文: `.ai/CODEX/RESULTS/T-OS-154R.md`

## Acceptance Criteria

### F1 [HIGH]: enforcement 強化
問題: request-intake-loop.md:405-407 で「Manager の自発的参照」に委ねている。Pro 指摘「制御システム化」未達。
修正:
- ルール本文に追記: 「本ループは OrgOS Manager の最高位 Iron Law である。Manager は Step 1-10 を未実施のまま応答してはならない」
- 違反検出ロジックをルール内に記述 (eval のどの metric で検出されるか)
- T-OS-154b で manager.md に埋め込む予定の「Tick 先頭に Step 1-10 を固定フロー化」を示唆セクションに強化記述

### F2 [HIGH]: Step 5 → Step 6 の還元規則
問題: Step 5 の 4 変数分類 (reversibility / cost / security / destructiveness) から Step 6 のマトリクス行への落とし方が未定義。`act/ask/defer/refuse` 判定不能。
修正: Step 5 と Step 6 の間に **reduction table** を追加:

```yaml
# Risk reduction rules (Step 5 → Step 6 マトリクス)
reduction_rules:
  - condition: "security == high OR destructiveness == external"
    minimum_risk: "high"
  - condition: "cost_billing > 0 OR destructiveness == shared"
    minimum_risk: "medium"
  - condition: "security == medium"
    minimum_risk: "medium"
  - default: "low"

# reversibility の判定
reversibility_rules:
  - destructive_data_change: "irreversible"
  - external_communication: "irreversible"
  - git_push_main: "irreversible"
  - local_file_edit: "reversible"
  - default: "reversible"
```

これで Step 6 マトリクスの行 (高/中/低 risk × 可逆/不可逆) が決定的に導出される。

### F3 [HIGH]: 全 6 指標との対応
問題: request-intake-loop.md:409-417 で Step 2/3/4/9 しか指標と連動していない。Step 1/5/6/7/8/10 が未接続。
修正: 測定セクションを全 6 指標・全 10 ステップ対応表に拡張:

```markdown
## 測定 (Manager Quality Eval 6 指標との全面対応)

| 指標 | 影響する Step | 検出方法 |
|------|--------------|---------|
| repeated_question_rate | Step 2 (Load Memory) 違反 | past_qa 参照せずに質問 |
| context_miss_rate | Step 3 (Bind Work Graph) 違反 | 応答で全体文脈を示さない |
| unnecessary_owner_question_rate | Step 4 (Discover Capabilities) + Step 6 (Decide) 違反 | CAPABILITIES にあるのに Owner に依頼 |
| capability_reuse_rate | Step 4 違反 | 毎回 which で探索 |
| owner_delegation_burden | Step 6 違反 | ask 判定過剰 |
| decision_trace_completeness | Step 7 (Execute with Trace) + Step 9 (Update) 違反 | trace_id / verification / memory_updates 不足 |

追加の品質検出:
- Step 1 違反: 依頼原文未保存 → past_qa の source 参照不可
- Step 5 違反: risk 分類なしで実行 → 破壊的操作リスク
- Step 8 違反: 副作用検証なし → 潜在バグ
- Step 10 違反: Coherence 3 段階無視 → Owner 体験悪化
```

## Instructions

1. T-OS-154R (`.ai/CODEX/RESULTS/T-OS-154R.md`) を精読
2. request-intake-loop.md の該当箇所 (L163-169, L194-201, L405-407, L409-417) を修正
3. F1-F3 を順次適用 (最小差分)
4. 全体の整合性を保つ (他セクションへの影響を確認)
5. **重要**: 他ファイル (manager.md, CLAUDE.md) は編集禁止

## Reference
- `.ai/CODEX/RESULTS/T-OS-154R.md` - レビュー指摘 (SSOT)
- `.claude/rules/request-intake-loop.md` - 対象ファイル
- `.claude/evals/manager-quality/metrics.yaml` - 6 指標定義

## Report

`.ai/CODEX/RESULTS/T-OS-154F.md` + stdout:
1. 変更ファイル (1 つのはず)
2. F1-F3 対応表
3. reduction_rules の決定的例 (サンプル依頼 3 件で `act/ask` 判定の例)
4. ステータス: DONE / DONE_WITH_CONCERNS / BLOCKED
