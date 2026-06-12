# OWNER INBOX (Decision Console)

> Manager から Owner への決済依頼。各 Card に推奨 + デフォルト動作付き。
> 未応答 7 日で `default_if_no_response` が自動適用される (synthetic Owner approve のみ)。
> 質問への回答は: `echo "D-XXX A" >> .ai/OWNER_COMMENTS.md` または「D-XXX A」と発話。

## 高優先度決済 (response < 24h 推奨)

### D-2026-06-11-001 [type_a_direction] ISS-005: 開発リポジトリ全体が PUBLIC (Yokotani-Dev/OrgOS) に push 済み。配布モデルをどちらに確定するか（確定まで push 全面保留中）
- 推奨選択: B
- 回答: `echo "D-2026-06-11-001 <A|B|C>" >> .ai/OWNER_COMMENTS.md`

```decision-card
id: D-2026-06-11-001
type: type_a_direction
decision: 'ISS-005: 開発リポジトリ全体が PUBLIC (Yokotani-Dev/OrgOS) に push 済み。配布モデルをどちらに確定するか（確定まで push 全面保留中）'
recommendation: DEFER
recommendation_reason: OrgOS の .ai/ 台帳は Owner の業務内容・意思決定・作業パターンを含む。実害(secret)は未検出だが Chief of Staff の記録は private が原則。B は一度の手間で恒久的に安全
risk: high
options:
- key: A
  label: 公開直開発を正式採用
  consequence: 今の public 直 push を正式運用化。sessions/CODEX注文書/バックアップを gitignore + git 履歴から除去し、org-publish キュレーション配布は廃止。手間小だが公開リスク管理は gitignore 頼みになる
  is_recommended: false
- key: B
  label: private 復帰 + キュレーション公開再建（推奨）
  consequence: origin を private に戻し、公開側は manifest ベースの 1-commit/release で再構築。台帳・作業ログ・思考過程が外部に出ない。GitHub 設定変更 + 公開側履歴リセットが一度だけ必要
  is_recommended: true
- key: C
  label: 現状維持
  consequence: public のまま継続。実シークレットは未検出だが、台帳438ファイル(セッションログ・意思決定・タスク履歴)が公開され続ける。非推奨
  is_recommended: false
default_if_no_response: defer_7d
deadline: '2026-06-18T23:59:59+09:00'
status: pending
```

## 中優先度決済 (response < 7d)
(なし)

## 低優先度決済 (response < 30d)
(なし)

## Archived (resolved or expired)

| id | original | decision | recommendation | risk | default | status | resolved_at |
|---|---|---|---|---|---|---|---|
| D-2026-05-01-001 | T-TEST / 42f93d2c-843d-45d5-bfd8-c3055f5edd35 | CLAUDE.md への test 用 edit_claude_md 承認要求を失効扱いにする | REJECT | low | no_op | expired | 2026-05-01T00:00:00+09:00 |
| D-2026-05-01-002 | T-TEST-NOWAIT / f2d4d515-66e7-4219-9ea8-fc065a21b3d1 | CLAUDE.md への nowait test 用 edit_claude_md 承認要求を失効扱いにする | REJECT | low | no_op | expired | 2026-05-01T00:00:00+09:00 |
| D-2026-05-01-003 | T-TEST-EXPIRE / 6941fb8a-47bc-476c-ba5c-818f2d0701a1 | CLAUDE.md への timeout test 用 edit_claude_md 承認要求を失効扱いにする | REJECT | low | no_op | expired | 2026-05-01T00:00:00+09:00 |
| D-2026-05-01-004 | T-TEST / 893fef4b-3708-4060-8543-7b7af834dfab | CLAUDE.md への 動作確認 test 用 edit_claude_md 承認要求を失効扱いにする | REJECT | low | no_op | expired | 2026-05-01T00:00:00+09:00 |

### D-2026-05-01-001 [type_a_direction] CLAUDE.md への test 用 edit_claude_md 承認要求を失効扱いにする
- 推奨選択: A
- 回答: archived のため不要

```decision-card
id: D-2026-05-01-001
type: type_a_direction
decision: "CLAUDE.md への test 用 edit_claude_md 承認要求を失効扱いにする"
recommendation: REJECT
recommendation_reason: "2026-04-19 15:25 の test 承認要求は 7 日を超えて未応答で、実運用の決済ではないため失効が最も保守的。"
risk: low
options:
  - key: A
    label: REJECT
    consequence: "test 承認要求を失効扱いにし、CLAUDE.md は変更しない。"
    is_recommended: true
  - key: B
    label: DEFER
    consequence: "追加 7 日保留するが、テスト残滓の滞留を延ばす。"
    is_recommended: false
  - key: C
    label: APPROVE
    consequence: "古い test 承認要求を承認する。OS 中核ファイル変更の意図が不明なため非推奨。"
    is_recommended: false
default_if_no_response: no_op
deadline: "2026-04-26T15:25:00+09:00"
synthetic_owner_judgment:
  verdict: reject
  confidence: 0.95
status: expired
resolved_at: "2026-05-01T00:00:00+09:00"
source:
  original_id: T-TEST
  operation: edit_claude_md
  target: CLAUDE.md
  request_id: 42f93d2c-843d-45d5-bfd8-c3055f5edd35
  summary: test
  impact: test
```

### D-2026-05-01-002 [type_a_direction] CLAUDE.md への nowait test 用 edit_claude_md 承認要求を失効扱いにする
- 推奨選択: A
- 回答: archived のため不要

```decision-card
id: D-2026-05-01-002
type: type_a_direction
decision: "CLAUDE.md への nowait test 用 edit_claude_md 承認要求を失効扱いにする"
recommendation: REJECT
recommendation_reason: "2026-04-19 15:25 の nowait test 承認要求は 7 日を超えて未応答で、実運用の決済ではないため失効が最も保守的。"
risk: low
options:
  - key: A
    label: REJECT
    consequence: "test 承認要求を失効扱いにし、CLAUDE.md は変更しない。"
    is_recommended: true
  - key: B
    label: DEFER
    consequence: "追加 7 日保留するが、テスト残滓の滞留を延ばす。"
    is_recommended: false
  - key: C
    label: APPROVE
    consequence: "古い test 承認要求を承認する。OS 中核ファイル変更の意図が不明なため非推奨。"
    is_recommended: false
default_if_no_response: no_op
deadline: "2026-04-26T15:25:00+09:00"
synthetic_owner_judgment:
  verdict: reject
  confidence: 0.95
status: expired
resolved_at: "2026-05-01T00:00:00+09:00"
source:
  original_id: T-TEST-NOWAIT
  operation: edit_claude_md
  target: CLAUDE.md
  request_id: f2d4d515-66e7-4219-9ea8-fc065a21b3d1
  summary: test
  impact: test
```

### D-2026-05-01-003 [type_a_direction] CLAUDE.md への timeout test 用 edit_claude_md 承認要求を失効扱いにする
- 推奨選択: A
- 回答: archived のため不要

```decision-card
id: D-2026-05-01-003
type: type_a_direction
decision: "CLAUDE.md への timeout test 用 edit_claude_md 承認要求を失効扱いにする"
recommendation: REJECT
recommendation_reason: "2026-04-19 15:26 の timeout test 承認要求は 7 日を超えて未応答で、実運用の決済ではないため失効が最も保守的。"
risk: low
options:
  - key: A
    label: REJECT
    consequence: "test 承認要求を失効扱いにし、CLAUDE.md は変更しない。"
    is_recommended: true
  - key: B
    label: DEFER
    consequence: "追加 7 日保留するが、テスト残滓の滞留を延ばす。"
    is_recommended: false
  - key: C
    label: APPROVE
    consequence: "古い test 承認要求を承認する。OS 中核ファイル変更の意図が不明なため非推奨。"
    is_recommended: false
default_if_no_response: no_op
deadline: "2026-04-26T15:26:00+09:00"
synthetic_owner_judgment:
  verdict: reject
  confidence: 0.95
status: expired
resolved_at: "2026-05-01T00:00:00+09:00"
source:
  original_id: T-TEST-EXPIRE
  operation: edit_claude_md
  target: CLAUDE.md
  request_id: 6941fb8a-47bc-476c-ba5c-818f2d0701a1
  summary: timeout test
  impact: timeout test
```

### D-2026-05-01-004 [type_a_direction] CLAUDE.md への 動作確認 test 用 edit_claude_md 承認要求を失効扱いにする
- 推奨選択: A
- 回答: archived のため不要

```decision-card
id: D-2026-05-01-004
type: type_a_direction
decision: "CLAUDE.md への 動作確認 test 用 edit_claude_md 承認要求を失効扱いにする"
recommendation: REJECT
recommendation_reason: "2026-04-19 15:27 の動作確認 test 承認要求は 7 日を超えて未応答で、実運用の決済ではないため失効が最も保守的。"
risk: low
options:
  - key: A
    label: REJECT
    consequence: "test 承認要求を失効扱いにし、CLAUDE.md は変更しない。"
    is_recommended: true
  - key: B
    label: DEFER
    consequence: "追加 7 日保留するが、テスト残滓の滞留を延ばす。"
    is_recommended: false
  - key: C
    label: APPROVE
    consequence: "古い test 承認要求を承認する。OS 中核ファイル変更の意図が不明なため非推奨。"
    is_recommended: false
default_if_no_response: no_op
deadline: "2026-04-26T15:27:00+09:00"
synthetic_owner_judgment:
  verdict: reject
  confidence: 0.95
status: expired
resolved_at: "2026-05-01T00:00:00+09:00"
source:
  original_id: T-TEST
  operation: edit_claude_md
  target: CLAUDE.md
  request_id: 893fef4b-3708-4060-8543-7b7af834dfab
  summary: 動作確認
  impact: test only
```
