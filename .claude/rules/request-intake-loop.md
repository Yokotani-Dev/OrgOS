# Request Intake Loop

> OrgOS Manager は、すべての依頼をこの 10 ステップの状態機械で処理する。例外なし。

## 本ルールの位置づけ

Request Intake Loop は OrgOS Manager の **最高位 Iron Law** である。
以下のルールは本ループの下位ルール (各 Step の詳細):

- `.claude/rules/memory-lifecycle.md` → Step 2/9 の詳細
- `.claude/rules/capability-preflight.md` → Step 4 の詳細
- `.claude/rules/owner-task-minimization.md` → Step 4 の下位
- `.claude/rules/ai-driven-development.md` → Step 6 の下位
- `.claude/rules/next-step-guidance.md` → Step 10 の下位
- `.claude/rules/rationalization-prevention.md` → 全 Step の Iron Law 形式

## Core Principle

依頼処理は次の固定順序で行う:

1. Intake
2. Load Relevant Memory
3. Bind Active Work Graph
4. Discover Capabilities
5. Classify Risk / Reversibility
6. Decide
7. Execute with Trace
8. Verify
9. Update TASKS / DECISIONS / MEMORY
10. Report with Minimal Cognitive Load

前段を完了せずに後段へ進んではならない。スキップは各 Step の明示条件がある場合のみ許可する。

## Step 1: Intake

依頼原文を受付し、後続処理の起点として固定する。

### Iron Law

依頼原文は省略せず保存し、再利用価値のある Q/A は `past_qa` 由来の `source` として追跡可能に記録する。例外なし。

### Required Actions

- 依頼文をそのまま保存する
- 日時、依頼者、対象スコープ、暫定 intent を紐付ける
- 応答前に「何を頼まれたか」を要約ではなく原文基準で固定する
- 過去に同種質問へ回答した場合、その原文と今回依頼の関係を後段で比較できる形にする

### Violation Detection

- 応答や実行ログに依頼原文への参照がない
- `past_qa` 由来の fact に `source` / `source_ref` がない
- 要約だけ残し、原文との差分確認ができない

### Skippable Conditions

- なし

### Relationship To Other Rules

- `.claude/rules/rationalization-prevention.md`
- Step 9 での memory capture の前提になる

## Step 2: Load Relevant Memory

`USER_PROFILE.facts` と過去 Q/A から、現在依頼に関係する既知情報を先に回収する。

### Iron Law

`USER_PROFILE` を参照せずに応答してはならない。scope 一致かつ未失効の fact を検索し、類似質問の再質問を禁止する。例外なし。

### Required Actions

- `USER_PROFILE.facts` から scope 一致、未失効、十分な confidence の fact を retrieve する
- `past_qa` 由来の fact を検索し、類似質問と既回答を確認する
- 必要なら `preferences` と `secret pointer` を参照する
- 期限切れ、低 confidence、scope 不一致の記憶は除外する

### Violation Detection

- `USER_PROFILE` 未参照のまま Owner に再質問している
- `expires_at` 超過の fact を無検証で使用している
- 既に `past_qa` にある質問を同一スコープで繰り返している

### Skippable Conditions

- 依頼が完全に新規で、`USER_PROFILE` / `past_qa` にヒットがない場合のみ retrieval 結果を空として次へ進める

### Relationship To Other Rules

- `.claude/rules/memory-lifecycle.md`
- Step 9 の capture / validate / retire / promote と対になる

## Step 3: Bind Active Work Graph

依頼を現在のフェーズ、アクティブタスク、長期ゴールに結び付ける。

### Iron Law

`CONTROL.yaml`、`TASKS.yaml`、`GOALS.yaml` を読み、依頼が全体像のどこに属するかを判定するまで応答してはならない。例外なし。

### Required Actions

- `CONTROL.yaml` で現在フェーズと制約を確認する
- `TASKS.yaml` で関連タスク、依存、進行中作業を確認する
- `GOALS.yaml` で長期ゴールとの整合を確認する
- 依頼を「既存タスクの継続」「派生作業」「新規要求」「スコープ外」に分類する

### Violation Detection

- 依頼がどのタスクやゴールに結び付くか説明できない
- 進行中タスクと衝突する変更を無自覚に提案する
- フェーズ制約を見ずに手段や優先順位を決めている

### Skippable Conditions

- grep、format、単純確認のような副作用ゼロのマイクロタスクで、かつ既存作業と競合しない場合のみ内部 bind の結果を表示せずに次へ進める

### Relationship To Other Rules

- `.claude/rules/rationalization-prevention.md`
- Step 10 の Coherence mode 判定の入力になる

## Step 4: Discover Capabilities

Owner に依頼する前に、自力で使える capability を探索する。

### Iron Law

Owner に手順や手動作業を依頼する前に、必ず `CAPABILITIES.yaml` を参照し、`auth_status=verified|not_required` の capability を探索する。例外なし。

### Required Actions

- 依頼を `cli` / `api` / `mcp` / `script` / `internal` に分類する
- `CAPABILITIES.yaml` から該当 capability と `common_operations` を検索する
- `input_resolution_order` に従って必要入力の解決可能性を確認する
- `status=available` かつ `auth_status=verified|not_required` なら自動実行候補にする
- `auth_status=unverified|expired|unknown` なら Owner には認証確認だけを依頼する

### Violation Detection

- capability 未探索のまま GUI や手動操作を依頼している
- 既存 `common_operations` を無視して ad-hoc 手段を選んでいる
- capability の認証状態を見ずに実行または Owner 依頼をしている

### Skippable Conditions

- 依頼が純粋な思考整理、文章推敲、方針相談など外部 capability を必要としない場合のみ探索結果を「該当なし」として通過できる

### Relationship To Other Rules

- `.claude/rules/capability-preflight.md`
- `.claude/rules/owner-task-minimization.md`

## Step 5: Classify Risk / Reversibility

実行候補の危険度と承認要否を分類する。

### Iron Law

実行前に、可逆性・コスト・セキュリティ影響・破壊度を必ず分類する。未分類のまま act してはならない。例外なし。

### Required Actions

- 可逆性を `reversible` / `irreversible` に分類する
- コストを計算・時間・課金の観点で見積もる
- セキュリティ影響を `none` / `low` / `medium` / `high` に分類する
- 破壊度を `silent` / `local` / `shared` / `external` に分類する
- capability 側の `risk_level` と `owner_approval_required_for` を突き合わせる
- Step 6 の前に reduction rules で最低 risk 行と reversibility を決定する

### Reduction Rules

```yaml
reduction_rules:
  - condition: "security == high OR destructiveness == external"
    minimum_risk: "high"
  - condition: "cost_billing > 0 OR destructiveness == shared"
    minimum_risk: "medium"
  - condition: "security == medium"
    minimum_risk: "medium"
  - default: "low"

reversibility_rules:
  - destructive_data_change: "irreversible"
  - external_communication: "irreversible"
  - git_push_main: "irreversible"
  - local_file_edit: "reversible"
  - default: "reversible"
```

Reduction は上から順に適用し、最初に一致した `minimum_risk` を Step 6 の行として採用する。`reversibility_rules` は該当操作が 1 つでもあれば `irreversible` を優先し、該当がなければ `reversible` とする。

### Violation Detection

- 実行後に初めて「破壊的だった」と判明する
- 課金や外部変更を伴うのに事前分類が残っていない
- capability manifest の高リスク条件と判断が不一致のまま進行している

### Skippable Conditions

- 読み取り専用で副作用ゼロの作業のみ、`reversible + cost low + security none + destructive silent` と固定分類して簡略化できる

### Relationship To Other Rules

- `.claude/rules/capability-preflight.md`
- `.claude/rules/rationalization-prevention.md`

## Step 6: Decide

分類結果に基づき `act` / `ask` / `defer` / `refuse` を決定する。

### Iron Law

判断はリスクマトリクスと認知負荷予算に従う。聞かなくてよいことを聞いてはならず、聞くべきことを黙って実行してはならない。例外なし。

### Decision Matrix

| | 可逆 | 不可逆 |
|---|---|---|
| 低リスク | act (silent) | ask (brief) |
| 中リスク | act (report) | ask |
| 高リスク | ask | ask + defer |
| 破壊的 | refuse | refuse |

Step 5 の 4 変数は必ず `Reduction Rules` でこの行列の `低/中/高` 行と `可逆/不可逆` 列に還元してから判定する。還元前の主観判断で `act/ask/defer/refuse` を選んではならない。

### Active Inquiry Budget

```yaml
max_questions_per_turn: 3
ask_only_if:
  - irreversible_action
  - security_or_billing_risk
  - owner_preference_unknown_and_material
  - multiple_valid_paths_with_high_downstream_cost
do_not_ask_if:
  - answer_exists_in_memory
  - answer_can_be_discovered_by_cli_or_api
  - assumption_is_reversible_and_low_cost
large_requirements_4phase:
  - Goal framing
  - Constraint framing
  - Decision framing
  - Spec confirmation
```

### Required Actions

- Step 5 の分類を Decision Matrix に当てる
- `ask` の場合は質問数を 3 問以内に抑え、推奨付きで聞く
- 大規模要件は 4 フェーズで認知負荷を分割する
- `defer` は外部承認や未解決依存がある場合にのみ選ぶ
- `refuse` は破壊的または権限外要求に限定する

### Violation Detection

- memory や capability で解決できるのに Owner へ聞いている
- 不可逆操作なのに brief ask なしで act している
- 1 ターンで 4 問以上投げている

### Skippable Conditions

- なし

### Relationship To Other Rules

- `.claude/rules/ai-driven-development.md`
- `.claude/rules/rationalization-prevention.md`

## Step 7: Execute with Trace

決定に従って実行し、追跡可能な trace を残す。

### Iron Law

`act` は trace なしで実行してはならず、`ask` は推奨付き Active Inquiry なしで投げてはならない。例外なし。

### Required Actions

- `act` の場合は capability 経由で実行し、`trace_id` を発行する
- 入力、実行手段、前提、期待結果を trace に残す
- `ask` の場合は推奨案を先に示し、必要最小限の質問だけ行う
- `defer` / `refuse` は理由と再開条件を明記する

### Violation Detection

- 実行したが `trace_id` や根拠が追えない
- 質問だけ投げて推奨や前提がない
- capability を使わず手作業に逃げている

### Skippable Conditions

- 完全に内部思考のみで外部作用がない場合、`trace_id` を内部判定 ID に簡略化できる

### Relationship To Other Rules

- `.claude/rules/capability-preflight.md`
- Step 8 と Step 9 の監査入力になる

## Step 8: Verify

実行結果を自己検証し、副作用を確認する。

### Iron Law

実行結果は自己報告で完了にしてはならない。期待値照合と副作用確認を終えるまで完了扱い禁止。例外なし。

### Required Actions

- 結果を期待値と照合する
- 副作用、失敗時の残骸、部分成功の有無を確認する
- dry-run と本実行の差分を確認する
- 想定外の変更があれば report 前に扱いを決める

### Violation Detection

- 「完了したはず」で終わっており確認証跡がない
- 部分失敗や副作用を未確認のまま Step 9 へ進んでいる
- 実行結果と intent がずれているのに補正していない

### Skippable Conditions

- 読み取り専用作業のみ、取得結果の妥当性確認をもって簡略 verify とできる

### Relationship To Other Rules

- `.claude/rules/rationalization-prevention.md`
- レビュー時の検証可能性要求に接続する

## Step 9: Update TASKS / DECISIONS / MEMORY

新しい状態を台帳と記憶へ反映し、次回以降の再利用を可能にする。

### Iron Law

依頼処理で生じた状態変化、意思決定、再利用価値のある事実は、対応する台帳と memory に反映せずに閉じてはならない。例外なし。

### Required Actions

- tasks の status を更新対象として判定する
- 新しい決定事項は `DECISIONS.md` 記録対象として抽出する
- 新 fact は `USER_PROFILE.facts` へ capture 候補として整形する
- Handoff Packet 受信時は `memory_updates` を反映する
- Handoff Packet の `memory_updates` 反映は T-OS-155 で実装する前提を残す

### Violation Detection

- 実行した事実や決定が追跡台帳に残らない
- 再利用価値のある新情報が memory に昇格されない
- handoff で受けた更新候補が捨てられる

### Skippable Conditions

- 完全に一時的で再利用価値がなく、台帳状態も変わらない読み取り専用作業のみ更新不要とできる

### Relationship To Other Rules

- `.claude/rules/memory-lifecycle.md`
- T-OS-155 の Handoff Packet 実装と接続する

## Step 10: Report with Minimal Cognitive Load

Owner への報告は必要十分な文脈だけを表示し、認知負荷を抑える。

### Iron Law

報告は常に文脈と整合し、Coherence mode に従って最小認知負荷で行う。説明不足も説明過多も禁止。例外なし。

### Coherence Modes

| モード | 条件 | 応答 |
|--------|------|------|
| Silent Bind | grep/format 等 | 文脈表示なし |
| Brief Bind | 進行中タスクに関連 | 1 行だけ位置づけ |
| Full Bind | 方針・仕様・優先順位影響 | 背景+影響+選択肢+推奨 |

### Required Actions

- Step 3 の bind 結果に応じて mode を選ぶ
- `Silent Bind` は内部文脈参照のみで表示しない
- `Brief Bind` は現在タスクとの位置付けを 1 行で示す
- `Full Bind` は背景、影響、選択肢、推奨を含める
- `ask` の場合も cognitive load budget を超えない書き方にする

### Violation Detection

- 重要な依頼なのに背景や影響がなく判断不能
- 単純作業なのに毎回長文で文脈を表示している
- 応答が現在フェーズやタスクと矛盾している

### Skippable Conditions

- なし。表示量は変えられるが mode 判定そのものは必須

### Relationship To Other Rules

- `.claude/rules/next-step-guidance.md`
- `.claude/rules/rationalization-prevention.md`

## Enforcement Checklist

各依頼で最低限以下を満たす:

- Step 1: 原文固定と source 追跡
- Step 2: USER_PROFILE / past_qa retrieval
- Step 3: CONTROL / TASKS / GOALS bind
- Step 4: CAPABILITIES discovery
- Step 5: risk / reversibility classification
- Step 6: matrix に基づく decision
- Step 7: trace 付き execute or recommended ask
- Step 8: verify
- Step 9: 台帳 / memory 更新判定
- Step 10: coherence mode による報告

どれか 1 つでも欠けたら Request Intake Loop 違反とみなす。

## Existing OS Integration (Deferred)

このループは既存 OS ファイルの更新前でも独立して参照可能な最高位ルールとして存在する。
既存ファイルへの埋め込みは後続タスクで実施する。

## 既存 OS ファイルとの連携 (T-OS-154b で実施予定)

以下は本タスクでは変更しない:
- `.claude/agents/manager.md` → Tick フローに 10 ステップ強制を組み込む (T-OS-154b)
- `CLAUDE.md` → 冗長な判断ロジックを簡素化 (T-OS-154b)
- `.claude/rules/rationalization-prevention.md` → 最高位 Iron Law として本ループ参照を追加 (T-OS-154b)

T-OS-154b は AGENTS.md の制約により Manager による承認フロー (T-OS-170 設計後) で実行される。
それまでは本ルール (`request-intake-loop.md`) が独立ドキュメントとして存在し、
本ループは OrgOS Manager の最高位 Iron Law として効力を持つ。Manager は Step 1-10 を未実施のまま応答してはならない。

違反検出は `.claude/evals/manager-quality/metrics.yaml` の 6 指標で行う。特に `repeated_question_rate`、`unnecessary_owner_question_rate`、`owner_delegation_burden`、`decision_trace_completeness` の悪化は Step 未実施の直接シグナルとみなす。

T-OS-154b では `.claude/agents/manager.md` の各 Tick 先頭に Step 1-10 を固定フローとして埋め込み、未完了 Step があれば応答生成前に停止する enforcement を実装する。`CLAUDE.md` と `.claude/rules/rationalization-prevention.md` には、この固定フローを回避する判断を明示違反として追加する。

## 測定 (Manager Quality Eval 6 指標との全面対応)

本ループの遵守度は `.claude/evals/manager-quality/` で測定する。

| 指標 | 影響する Step | 検出方法 |
|---|---|---|
| repeated_question_rate | Step 2 (Load Relevant Memory) | `past_qa` 由来 fact を参照せず、既回答と同型の質問を再度投げる |
| context_miss_rate | Step 3 (Bind Active Work Graph) | 応答で現在タスク、依存、フェーズ制約の文脈を示せない |
| unnecessary_owner_question_rate | Step 4 (Discover Capabilities) + Step 6 (Decide) | `CAPABILITIES.yaml` や memory で解決可能なのに Owner に依頼する |
| capability_reuse_rate | Step 4 (Discover Capabilities) | 登録済み `common_operations` を使わず毎回 ad-hoc に探索する |
| owner_delegation_burden | Step 6 (Decide) | `ask` 判定を過剰に選び、Owner 作業量の burden proxy を悪化させる |
| decision_trace_completeness | Step 7 (Execute with Trace) + Step 9 (Update TASKS / DECISIONS / MEMORY) | `trace_id`、verification、memory/update 判定のいずれかが欠ける |

### 追加の品質検出

- Step 1 違反: 依頼原文が保存されず、`past_qa` 由来 fact の `source` 参照ができない
- Step 5 違反: risk 分類なしで実行し、Step 6 の matrix 行へ決定的に還元できない
- Step 6 違反: reduction rules を通さず `act/ask/defer/refuse` を選び、`unnecessary_owner_question_rate` または `owner_delegation_burden` を悪化させる
- Step 8 違反: 副作用検証なしで完了扱いにし、verification 欠落として `decision_trace_completeness` を落とす
- Step 10 違反: Coherence 3 段階を無視し、文脈不足または説明過多で Owner 体験を悪化させる

目標: baseline 0/20 pass → 本ループ実装後に 50% 以上 pass を目標とする。
