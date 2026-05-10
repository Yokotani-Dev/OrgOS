# User Journey Sync - Iron Law

> 「何を作るか」ではなく、「何を実現したいか」と「そのためにどんな業務の流れで操作するか」を Owner と合意する。例外なし。

## Purpose

User Journey Sync は REQUIREMENTS フェーズの業務フロー合意ルールである。
BRIEF が persona / motive / success criteria を扱うのに対し、Journey は実際の操作手順を `As-Is -> To-Be -> happy_path -> error_paths` で固定する。

## Iron Law

1. **BRIEF 完了直後に Journey Workshop を実施する**。REQUIREMENTS で機能リストを作る前に、ToBe 業務フローを Owner と擦り合わせる。例外なし。
2. **機能は Journey の step から derive される**。「機能リスト → Journey 後付け」ではなく「Journey → 機能 derivation」の順序を必ず守る。
3. REQUIREMENTS から DESIGN へ進む前に、対象 milestone に紐づく Journey が `sync_status=confirmed` でなければならない。
4. 追加機能依頼で `target_flow` の変更を伴う場合、実装前に After Journey を Owner と合意しなければならない。
5. Journey は機能リストではなく業務フローである。画面や実装部品ではなく、Owner が実現したい操作の流れを記録する。
6. **Journey が `draft` のまま機能議論を進めない**。「Journey は後で書く、まず機能を考えよう」は Iron Law violation である。

## Required Data

Journey は `.claude/schemas/journey.yaml` に従い、実体は `.ai/JOURNEYS.yaml` に保存する。

必須の構成:

- `current_flow`: As-Is の業務手順と pain point
- `target_flow`: To-Be の業務手順と enabled_by
- `happy_path`: Owner が通常成功すると考える 3-5 ステップ
- `error_paths`: 代表的な失敗・例外と handling 2-3 件
- `sync_status`: `draft | confirmed | superseded`

## Journey Workshop Process

BRIEF 完了直後に Manager は以下の Workshop を Owner と実施する:

1. **Current Flow ヒアリング**: Owner が「現在どう業務を回しているか」または「現在の代替手段」を聞き取る
2. **Pain Point 抽出**: current_flow の各 step で「何が辛いか」「何が時間を食っているか」を明示化
3. **Target Flow Drafting**: Manager が ToBe 業務フローの draft を作る (Owner が一から書く負担を避ける)
4. **Owner レビュー**: Owner が draft を確認し、「ここはこうしたい」と修正する
5. **Happy Path / Error Paths 確定**: 通常成功フローと代表的失敗を確定
6. **sync_status=confirmed への昇格**: Owner が明示合意した時点で confirmed

**Workshop は機能リストの議論より前に実施する**。Journey が confirmed になってから初めて、各 step に必要な機能を derive する。

## 機能 Derivation Rule

機能 (features / functions) は **Journey の step から派生** させる。

良い例:
```yaml
journey_step: "User が物件を検索して候補を 5 件保存する"
derived_features:
  - feature_id: F-SEARCH-001
    derived_from: journey_step_3
    description: "条件指定での物件検索"
  - feature_id: F-SAVE-001
    derived_from: journey_step_3
    description: "候補保存 (最大 5 件)"
```

悪い例 (機能ベース思考):
```yaml
features:
  - "検索機能"
  - "保存機能"
  - "通知機能"  # ← なぜ必要? どの journey step を実現する?
```

機能には必ず `derived_from: journey_step_N` の追跡可能な根拠を付ける。Journey に紐付かない機能は **scope クリープ候補** として Owner 確認を要する。

## REQUIREMENTS Gate

REQUIREMENTS gate では次を満たすまで DESIGN に進んではならない。

- 関連 milestone に 1 件以上の Journey がある
- そのうち現在の開発対象を覆う Journey が `sync_status=confirmed`
- `confirmed_at` と `confirmed_by` が記録されている
- `target_flow` が Owner 確認済みで、実装都合だけで書かれていない
- 全機能が `derived_from` で journey step に紐付いている

## Additional Feature Requests

Request Intake Loop Step 3 で追加依頼を Active Work Graph に結び付けるとき、次を判定する。

- 既存 Journey の `target_flow` に影響しない小修正なら、Journey 参照を記録して続行できる
- 操作手順、判断順序、例外対応、Owner の確認ポイントが変わるなら、After Journey を作成または既存 Journey を draft に戻す
- After Journey が `confirmed` になるまで、DESIGN または IMPLEMENTATION に着手してはならない

## Relationship To GOALS.yaml

Journey は GOALS.yaml の milestone に紐づく Work Graph レイヤーである。

- `1 milestone = 1+ journey`
- `related_milestone` は GOALS.yaml の `milestones[*].id` を参照する
- `related_tasks` は Journey 合意を実装・検証する TASKS.yaml の task id を参照する
- milestone の acceptance は「何が達成されたか」、Journey は「どの業務フローで達成するか」を表す

## Request Intake Loop Integration

- Step 3: Bind Active Work Graph で Journey 影響判定を行う。追加依頼が `target_flow` を変えるなら Journey sync を必須にする。
- Step 6: Decide で `act` を選ぶ前に、Journey 未確認なら `ask` または `defer` に落とす。
- Step 10: Report で Journey 参照、未確認点、Owner に求める確認を最小認知負荷で提示する。

## Red Flags

以下を検出したら作業を止める。

- BRIEF の直後に Journey 合意なしで DESIGN に着手している
- BRIEF の直後に Journey Workshop なしで REQUIREMENTS の機能リストを作り始めている
- 機能リストが先にあり、Journey が後付けで書かれている
- `target_flow` が Owner 未確認のまま実装タスクへ分解されている
- UX、操作順、例外対応を変えたのに Journey が更新されていない
- Journey が機能一覧、画面遷移図、コンポーネント一覧になっている
- `sync_status=confirmed` なのに `confirmed_at` または `confirmed_by` が null
- 機能に `derived_from: journey_step_N` の追跡可能な根拠がない

## Violation Detection

違反検出は後続タスクで runtime gate に接続する。

- T-OS-312: `/org-tick` の REQUIREMENTS gate で `sync_status=confirmed` をチェックする
- T-OS-313: `request-intake-loop` Step 3 で Journey 影響判定を追加する
- Manager Quality Eval: BRIEF 直後 DESIGN 着手、Owner 未確認 target_flow 実装、UX 変更時の Journey 未更新を regression case に追加する

## Violation Response

- REQUIREMENTS gate 違反は DESIGN 進行を停止する
- 追加機能で After Journey 未確認なら実装を defer し、Owner に確認すべき業務フロー差分だけを提示する
- confirmed Journey の内容が古くなった場合は、既存 Journey を `superseded` にし、新しい Journey を `draft -> confirmed` で合意する
