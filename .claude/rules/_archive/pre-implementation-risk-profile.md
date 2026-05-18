> **ARCHIVED 2026-05-17**: This rule is superseded by the kernel.
> See `.ai/DECISIONS.md#PLAN-UPDATE-WEEK8-AUDIT` for rationale.

# Pre-Implementation Risk Profile - Iron Law

> DESIGN フェーズで脅威・データ全体・権限境界・トランザクション境界・冪等性を固定する。
> IMPLEMENTATION 後のセルフレビューは「観点の発見」ではなく「事前に固定した観点の漏れ確認」に格下げする。

## Purpose

Pre-Implementation Risk Profile は、実装前に壊れやすい境界を明示し、実装後レビューで Race condition、重複 insert、権限漏れ、データ漏洩、入力検証欠落が順番に発掘され続ける構造を止めるための DESIGN フェーズ必須ルールである。

Manager は DESIGN 完了時点で以下の 3 文書を confirmed にし、トランザクション境界と冪等性戦略を固定してから IMPLEMENTATION に進める。

- `THREAT_MODEL.md`
- `DATA_MODEL_FULL.md`
- `AUTHORITY_BOUNDARY.md`

## Iron Law

1. DESIGN フェーズ完了の定義には、`THREAT_MODEL.md`、`DATA_MODEL_FULL.md`、`AUTHORITY_BOUNDARY.md` の 3 文書が存在し、対象 milestone / project に対して `confirmed` であることを必ず含める。
2. 脅威モデルが confirmed でない状態で IMPLEMENTATION に着手してはならない。これは `quality_level` や納期に関係なく停止条件である。
3. データモデル全体図が confirmed でない状態で、個別テーブル、migration、永続化ロジック、状態更新ロジックを設計または実装してはならない。
4. RLS、RPC / Function 権限、認証境界、認可判断点を `AUTHORITY_BOUNDARY.md` に明示せずに、認証コード、認可コード、admin 機能、user-scoped query を書いてはならない。
5. トランザクション境界と冪等性 key は IMPLEMENTATION 前に `DATA_MODEL_FULL.md` で決定しなければならない。後から「必要そうなら足す」は Iron Law violation である。
6. Threat Categories の 8 項目は全て評価し、対象外の場合も `該当なし` と理由を記録しなければならない。
7. 実装後セルフレビューで critical / major risk が初発見された場合、Manager は DESIGN 成果物の漏れとして扱い、該当文書を更新してから修正タスクを切らなければならない。

## Required Artifacts

### THREAT_MODEL.md

必須内容:

- 8 Threat Categories 全ての該当判定
- 該当箇所: flow / table / endpoint / job / UI action
- 攻撃または失敗シナリオ
- 実装対策
- 検証方法
- プロジェクト固有脅威

### DATA_MODEL_FULL.md

必須内容:

- 全テーブル一覧
- ER 図
- 主要 entity の状態遷移
- 不変条件
- トランザクション境界
- 冪等性 key
- 削除戦略

### AUTHORITY_BOUNDARY.md

必須内容:

- ロール一覧
- リソースごとの CRUD 権限マトリクス
- RLS policy 一覧
- RPC / Function 権限一覧
- 認証境界
- セッション管理
- 監査ログ要件

## Threat Categories

以下 8 カテゴリは網羅必須である。カテゴリを省略してはならない。

| # | Category | 必ず見る観点 |
|---|---|---|
| 1 | Race condition (同時更新) | 同一 resource への同時 write、在庫・枠・残高・状態遷移、retry 時の二重適用 |
| 2 | 重複 (idempotency 不在) | 二重 submit、webhook retry、job retry、ネットワーク再送、同一 intent の重複 insert |
| 3 | 権限漏れ (RLS / authz) | user scope、tenant scope、admin-only 操作、owner check、policy bypass |
| 4 | 認証回避 (authn) | anonymous access、token 欠落、session 失効、callback / webhook 署名、middleware bypass |
| 5 | データ漏洩 (PII / secret) | PII、secret、credential、internal id、error message、log、cache、export |
| 6 | 暴走 (無限ループ / リソース枯渇) | unbounded loop、recursive job、巨大 payload、N+1、rate limit 不在、queue backpressure |
| 7 | 入力検証欠落 (injection / XSS) | SQL / command injection、XSS、path traversal、schema validation、content sanitization |
| 8 | エラー隠蔽 (silent failure) | catch-and-ignore、partial success、retry exhaustion、監視不能、user に失敗が伝わらない |

## DESIGN Gate

Manager は DESIGN から IMPLEMENTATION へ遷移する前に、以下を deterministic に判定する。

```yaml
pre_implementation_risk_profile_gate:
  required_documents:
    threat_model:
      path: ".ai/DESIGN/THREAT_MODEL.md"
      status: "confirmed"
    data_model_full:
      path: ".ai/DESIGN/DATA_MODEL_FULL.md"
      status: "confirmed"
    authority_boundary:
      path: ".ai/DESIGN/AUTHORITY_BOUNDARY.md"
      status: "confirmed"
  required_fields:
    threat_categories_count: 8
    transaction_boundaries_present: true
    idempotency_strategy_present: true
    authority_matrix_present: true
  if_missing: "block_implementation"
```

3 文書の confirmed が揃わない場合、IMPLEMENTATION タスクを queued / in_progress にしてはならない。Manager は `blocked_by_design_gate` として止め、Owner には不足文書と判断待ちの論点だけを提示する。

## Self-Review Reframing

実装後セルフレビューの役割は、実装前に固定した観点がコードへ反映されたかを確認することである。

- セルフレビューで新しい threat category を発見するのは正常運用ではない。
- セルフレビューで critical / major risk が初めて出た場合、原因は実装品質だけでなく DESIGN 入力漏れとして扱う。
- レビュー指摘は `THREAT_MODEL.md`、`DATA_MODEL_FULL.md`、`AUTHORITY_BOUNDARY.md` のどの観点に対応するかを必ず紐付ける。
- 事前文書にない観点の指摘が出たら、修正前に DESIGN 文書を更新し、以後の Work Order に反映する。

## Red Flags

以下を検出したら IMPLEMENTATION を止める。

1. `THREAT_MODEL.md` が存在しない、または confirmed でない。
2. Threat Categories が 8 件未満である。
3. `DATA_MODEL_FULL.md` なしに migration / schema / repository 実装が始まっている。
4. ER 図がなく、個別テーブルだけが設計されている。
5. 主要 entity の状態遷移または不変条件が書かれていない。
6. トランザクション境界が「実装時に決める」と書かれている。
7. 冪等性 key が未定義のまま create / webhook / retryable job を実装している。
8. `AUTHORITY_BOUNDARY.md` なしに RLS、auth middleware、admin endpoint、RPC を実装している。
9. 権限マトリクスに anonymous / authenticated / admin / service role の区別がない。
10. エラー隠蔽、監査ログ、PII / secret の扱いが threat model に出ていない。

## Violation Detection

検出ポイント:

- `/org-tick` の DESIGN gate で 3 文書の存在と confirmed status を確認する。
- IMPLEMENTATION Work Order 生成時に 3 文書への参照を必須化する。
- Codex Work Order に `Quality Contract Reference` と 3 文書の参照がない場合は受理しない。
- Manager Quality Eval に `critical_leak_rate` を追加できる形で、実装後レビューで初発見された critical / major risk を記録する。

推奨 structured log:

```yaml
event: "pre_implementation_risk_profile_gate"
task_id: "T-..."
milestone_id: "M-..."
documents:
  threat_model: "confirmed|missing|draft"
  data_model_full: "confirmed|missing|draft"
  authority_boundary: "confirmed|missing|draft"
threat_categories_count: 8
transaction_boundaries_present: true
idempotency_strategy_present: true
critical_leak_rate_input:
  post_implementation_critical_findings: 0
  findings_missing_from_design_artifacts: 0
decision: "allow|block"
```

## Violation Response

Manager は違反を分類し、復旧手順を明示する。

| Violation | Classification | Manager Response | Recovery |
|---|---|---|---|
| 3 文書のいずれかが missing / draft | gate_blocker | IMPLEMENTATION を開始しない | 不足文書を生成し confirmed へ進める |
| Threat Categories が 8 件未満 | design_incomplete | DESIGN を差し戻す | 8 カテゴリを全て評価し、該当なし理由も記録する |
| トランザクション境界 / 冪等性 key 未定義 | consistency_risk | write 系実装を停止する | `DATA_MODEL_FULL.md` に atomic operation と key を追記する |
| 権限境界未定義 | security_risk | auth / RLS / RPC 実装を停止する | `AUTHORITY_BOUNDARY.md` に role、policy、boundary を追記する |
| 実装後レビューで critical 初発見 | design_escape | 修正タスク前に DESIGN 文書を更新する | `critical_leak_rate` に記録し、該当 Work Order を再発行する |

## Relationship To Other Rules

- `.claude/rules/design-documentation.md`: DESIGN フェーズで 3 文書を自動生成する接続点。
- `.claude/rules/quality-contract.md`: Quality Contract の security / error_handling / observability を実装前リスクへ展開する。
- `.claude/rules/user-journey-sync.md`: Journey の happy_path / error_paths から threat scenario と transaction boundary を derive する。
- `.claude/rules/request-intake-loop.md`: Step 5 の Risk classification で本ルールの成果物を参照する。
- `.claude/rules/eval-loop.md`: Manager Quality Eval の `critical_leak_rate` に DESIGN 漏れを入力する。
