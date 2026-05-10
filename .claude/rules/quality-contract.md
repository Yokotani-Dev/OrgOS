# Quality Contract Protocol — Iron Law

> 「サクッと作る」「PoC のつもりでした」を構造的に封じる。
> 品質目標は Owner と事前に擦り合わせ、`sync_status=confirmed` になるまで IMPLEMENTATION に進めない。例外なし。

## Purpose

OrgOS Manager は「自律実行 > 確認待ち」preference に従い、何も言われなければ最速で動くものを作りに行く Default を持つ。
この Default は「進め方」については正しいが、「**ゴール基準**」に適用すると「Owner が想定した品質」と「Manager が選んだ品質」のギャップを生む。

Quality Contract は **進め方の自律性は維持しつつ、ゴール基準だけを Owner と明示合意する** protocol である。

## Iron Law

1. **IMPLEMENTATION フェーズに進む前に**、対象 milestone / project に紐づく Quality Contract が `sync_status=confirmed` でなければならない。
2. Manager が独断で `quality_level` を選んではならない。`prototype` / `poc` / `mvp` / `production` は Owner との明示合意事項である。
3. 実装中に `quality_level` を下げる判断 (例: production → mvp) を Owner 合意なしに行ってはならない。
4. Codex への Work Order には `quality_level` と `definition_of_done` を必ず含めなければならない。
5. 「とりあえず動くもの」を作りたい場合も、`quality_level=prototype` として Owner と confirmed しなければならない。

## Required Data

Quality Contract は `.claude/schemas/quality-contract.yaml` に従い、実体は `.ai/QUALITY_CONTRACTS.yaml` に保存する。

必須:

- `quality_level`: `prototype` / `poc` / `mvp` / `production`
- `definition_of_done`: 6 軸 (functionality / error_handling / security / performance / observability / documentation) で各 level を明示
- `scope_boundary.out_of_scope`: 明示的に「やらない」リスト
- `sync_status`: `draft | confirmed | superseded`
- `confirmed_at` / `confirmed_by` (confirmed 時)

## Quality Level の意味

| Level | 用途 | Definition of Done の典型 |
|---|---|---|
| `prototype` | 動作確認、捨てる前提 | functionality=happy_path_only, error=none, security=none |
| `poc` | 概念実証、limited scope | functionality=happy_path_only, error=log_only, security=basic_auth |
| `mvp` | 最小限の本番運用、特定 user | functionality=happy_path_plus_main_errors, error=user_visible_messages, security=full_authz_authn |
| `production` | フル本番、SLA あり | functionality=full_coverage, error=classified_with_recovery, security=audited_with_threat_model |

**重要**: これらは Manager が選ぶ menu ではなく、Owner と擦り合わせる starting point である。Owner が「production だが observability は後回し」と言えば、その通り contract に書く。

## REQUIREMENTS / IMPLEMENTATION Gate

REQUIREMENTS gate:
- 対象 milestone / project に Quality Contract draft が 1 件以上ある
- Owner と quality_level について擦り合わせ済み

IMPLEMENTATION gate:
- Quality Contract が `sync_status=confirmed`
- `confirmed_at` と `confirmed_by` が記録されている
- `definition_of_done` が 6 軸とも埋まっている
- `scope_boundary.out_of_scope` が明示されている (空配列でもよいが、"考えていない" は不可)

## Codex Work Order との連携

Manager が Codex に Work Order を出す際、以下を必ず含める:

```markdown
## Quality Contract Reference
- QC ID: QC-AUTH-001
- quality_level: mvp
- definition_of_done:
  - functionality: happy_path_plus_main_errors
  - error_handling: user_visible_messages
  - security: full_authz_authn (RLS + CSRF + rate_limit)
  - performance: smoke_check
  - observability: structured_logs
  - documentation: readme
- out_of_scope (実装するな):
  - admin dashboard
  - audit log persistence
  - i18n
```

Codex はこの contract に従って実装する。contract を超える実装 (over-engineering) も、下回る実装 (under-engineering) も Iron Law violation とする。

## Manager の自律判断境界

| 判断 | Manager 自律 | Owner 合意必要 |
|---|---|---|
| 実装手段 (どのライブラリ/パターン) | ✅ | — |
| 実装順序 (どのタスクを先に) | ✅ | — |
| `quality_level` の選択 | ❌ | ✅ |
| `definition_of_done` の各 level | ❌ (draft 提案は OK) | ✅ |
| `scope_boundary.out_of_scope` の確定 | ❌ (draft 提案は OK) | ✅ |
| `quality_level` の途中変更 | ❌ | ✅ |
| 実装中の追加機能 (out_of_scope を超える) | ❌ | ✅ |

## Owner Touchpoint としての位置付け

Quality Contract は Phase 2 SYNTHESIS の **Owner Touchpoint Type A (Direction)** に分類される。
「自律実行 > 確認待ち」と矛盾しない — むしろ Type A で品質を擦り合わせるからこそ、その後の Type B/C/D を完全自律化できる。

## Red Flags

以下を検出したら作業を止める:

- Quality Contract なしに IMPLEMENTATION 着手
- Manager が独断で `quality_level=poc` を選び「PoC のつもりで作りました」と後出し説明
- Codex Work Order に `quality_level` 記載がない
- 実装中に `quality_level` を勝手に下げる (production → mvp など)
- `scope_boundary.out_of_scope` を埋めていない (= scope クリープが起きる)
- `definition_of_done` の 6 軸のどれかが未記入

## Violation Detection

- `/org-tick` で IMPLEMENTATION ステージ遷移時に Quality Contract `sync_status=confirmed` をチェック
- Codex Work Order template に `quality_level` 必須化
- Manager Quality Eval に追加: 「PoC 言い訳」発生率、quality_level 後出し変更回数

## Violation Response

- Quality Contract 未 confirmed のまま IMPLEMENTATION 着手 → 即座に停止し、Owner に擦り合わせ要請
- Codex 実装が contract を超える → 該当部分は破棄、再実装
- Codex 実装が contract を下回る → 不足分を追加実装

## Relationship To Other Rules

- `.claude/rules/user-journey-sync.md`: Journey が「何のために」、Quality Contract が「どこまで作る」
- `.claude/rules/design-documentation.md`: DESIGN フェーズの設計品質と接続
- `.claude/rules/eval-loop.md`: 評価基準は Quality Contract の definition_of_done から derive
- `.claude/rules/request-intake-loop.md`: Step 5 (Risk classification) で quality_level を入力に使う
- `.claude/rules/authority-layer.md`: production 昇格は `owner_only` autonomy_level に該当
- `.claude/rules/ai-driven-development.md`: 「Manager が自律判断すること」リストから quality_level を明示的に除外
