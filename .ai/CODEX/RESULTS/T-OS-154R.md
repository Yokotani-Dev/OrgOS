# T-OS-154R Review Report

## 総合判定
- △ (要修正)

## 観点別評価
### R1: Pro 指摘「制御システム化」の達成度
- 判定: △
- 確認内容:
  - 10 ステップは固定順序の状態機械として宣言され、前段未完了で後段へ進めないこと、各 Step 欠落で違反とみなすことまで書かれている（`.claude/rules/request-intake-loop.md:17-32`, `.claude/rules/request-intake-loop.md:376-391`）。
  - 各 Step に `Iron Law` / `Violation Detection` / `Skippable Conditions` / `Relationship To Other Rules` が揃っており、単なる要約ではなく運用規則として整えられている（`.claude/rules/request-intake-loop.md:34-374`）。
- 問題点:
  - 文書末尾で「Manager は本ルールを自発的に参照・適用することで効力を持つ」としており、最高位 Iron Law なのに実運用上は任意参照になっている。Pro 指摘の「制御システム化」「全依頼に無条件適用」とはまだ言えない（`.claude/rules/request-intake-loop.md:393-407`）。
  - Step 3/5/7/9 に複数の簡略化条件があり、どこまでが「表示だけ簡略化」でどこからが「処理自体の省略」なのかが曖昧。抜け道を防ぐ文言が弱い（`.claude/rules/request-intake-loop.md:115-117`, `.claude/rules/request-intake-loop.md:177-179`, `.claude/rules/request-intake-loop.md:267-269`, `.claude/rules/request-intake-loop.md:328-330`）。

### R2: 各ステップの Iron Law 厳格性
- 判定: △
- 確認内容:
  - 全 Step に `例外なし` が入り、違反例も具体的に列挙されている（`.claude/rules/request-intake-loop.md:38-40`, `.claude/rules/request-intake-loop.md:68-70`, `.claude/rules/request-intake-loop.md:98-100`, `.claude/rules/request-intake-loop.md:128-130`, `.claude/rules/request-intake-loop.md:159-161`, `.claude/rules/request-intake-loop.md:190-192`, `.claude/rules/request-intake-loop.md:250-252`, `.claude/rules/request-intake-loop.md:280-282`, `.claude/rules/request-intake-loop.md:310-312`, `.claude/rules/request-intake-loop.md:341-343`）。
- 問題点:
  - 違反検出は多くが人間の解釈依存で、機械検出可能な証跡要件が不足している。たとえば Step 3 は `CONTROL/TASKS/GOALS` を読んだ証跡、Step 4 は capability lookup trace、Step 5 は分類結果の保存先、Step 10 は mode 判定ログが要求されていない（`.claude/rules/request-intake-loop.md:109-117`, `.claude/rules/request-intake-loop.md:140-148`, `.claude/rules/request-intake-loop.md:171-179`, `.claude/rules/request-intake-loop.md:361-369`）。
  - Step 7 の `trace_id` は要求されているが、形式・保存先・一意性条件がないため review での検出可能性が弱い（`.claude/rules/request-intake-loop.md:252-269`）。

### R3: 既存ルールとの階層関係
- 判定: △
- 確認内容:
  - 冒頭で下位ルールの対応表があり、`memory-lifecycle.md` を Step 2/9、`capability-preflight.md` を Step 4、`next-step-guidance.md` を Step 10 に接続している（`.claude/rules/request-intake-loop.md:5-15`）。
  - Step 2 は `memory-lifecycle.md` の retrieve / validate / capture と概ね整合し、Step 4 も `capability-preflight.md` の探索順序と大筋一致する（`.claude/rules/request-intake-loop.md:72-77`, `.claude/rules/memory-lifecycle.md:33-41`, `.claude/rules/memory-lifecycle.md:82-96`, `.claude/rules/request-intake-loop.md:132-138`, `.claude/rules/capability-preflight.md:7-21`）。
- 問題点:
  - `past_qa` の扱いが不整合。Request Intake Loop は Step 1/2/Enforcement Checklist で `past_qa` を独立の検索対象のように書いているが、`memory-lifecycle.md` は「`past_qa` は独立配列にしない。必ず fact として統一管理する」と明記している（`.claude/rules/request-intake-loop.md:40`, `.claude/rules/request-intake-loop.md:66`, `.claude/rules/request-intake-loop.md:75`, `.claude/rules/request-intake-loop.md:381`, `.claude/rules/memory-lifecycle.md:120-149`）。
  - Step 10 は `next-step-guidance.md` を下位ルールに置く一方、同ルールは「選択肢は出さない」を強く要求する。しかし Full Bind は「選択肢+推奨」を必須化しており、どちらが優先かの裁定が文書内にない（`.claude/rules/request-intake-loop.md:345-359`, `.claude/rules/next-step-guidance.md:19-25`, `.claude/rules/next-step-guidance.md:60-83`）。
  - Step 6 は `ai-driven-development.md` を下位に置くが、同ルールの「要件の曖昧さは最善の推測で進める」と、Request Intake Loop の `ask_only_if` / `multiple_valid_paths_with_high_downstream_cost` の境界が文書化されていない（`.claude/rules/request-intake-loop.md:203-229`, `.claude/rules/ai-driven-development.md:18-30`, `.claude/rules/ai-driven-development.md:34-46`）。

### R4: Step 6 (Decide) の決定マトリクス
- 判定: △
- 確認内容:
  - 可逆/不可逆 × リスクの 2 軸マトリクス、`ask_only_if` / `do_not_ask_if`、`max_questions_per_turn: 3`、4 フェーズ分割は入っている（`.claude/rules/request-intake-loop.md:194-229`）。
- 問題点:
  - Step 5 で分類するのは `可逆性`、`コスト`、`セキュリティ影響`、`破壊度` の 4 変数だが、Step 6 の表は `低/中/高/破壊的` の 1 軸に圧縮されている。どの組み合わせがどの行に落ちるかの還元規則がなく、同じ事象に対して reviewer ごとに判定がぶれる（`.claude/rules/request-intake-loop.md:163-169`, `.claude/rules/request-intake-loop.md:194-201`）。
  - Pro SSOT は `max_cognitive_load: low` を含む認知負荷予算モデルを求めていたが、本文は質問数制限しか具体値がなく、認知負荷そのものの上限が欠落している（`.ai/DESIGN/CHATGPT_PRO_REVIEW_2026-04-18.md:78-88`, `.claude/rules/request-intake-loop.md:203-220`）。
  - `defer` の選択条件は 1 行説明に留まり、`ask + defer` と `ask` の境界が曖昧。大規模要件 4 フェーズも「分割する」としか書いておらず、各フェーズで何を決めたら次へ進めるかの exit criteria がない（`.claude/rules/request-intake-loop.md:223-229`）。

### R5: Step 10 (Report) の Coherence 3 段階
- 判定: ○
- 確認内容:
  - Silent / Brief / Full Bind の 3 段階は明示され、文脈なし応答と冗長応答の両方を違反検出に入れている点は妥当（`.claude/rules/request-intake-loop.md:345-365`）。
  - Step 3 の bind 結果を Step 10 mode 判定に使う構造も、Pro SSOT の Coherence Layer に沿っている（`.ai/DESIGN/CHATGPT_PRO_REVIEW_2026-04-18.md:59-76`, `.claude/rules/request-intake-loop.md:119-122`, `.claude/rules/request-intake-loop.md:353-359`）。
- 問題点:
  - `進行中タスクに関連`、`方針・仕様・優先順位影響` は運用上は理解できるが、機械判定やレビュー判定に使う閾値がない。mode 選択ミスを安定して検出できる書き方には届いていない（`.claude/rules/request-intake-loop.md:347-359`）。

### R6: Manager Quality Eval との連動
- 判定: ×
- 確認内容:
  - 測定セクションはあり、Step 2/3/4/9 と主要指標の一部を関連付けている（`.claude/rules/request-intake-loop.md:409-417`）。
- 問題点:
  - Pro SSOT の baseline 6 指標は `repeated_question_rate`, `owner_delegation_burden`, `context_miss_rate`, `unnecessary_owner_question_rate`, `capability_reuse_rate`, `decision_trace_completeness` だが、本文で接続されているのは 4 指標だけ。`owner_delegation_burden` が落ちており、`decision_trace_completeness` は Step 7 ではなく Step 9 にだけ結び付けられている（`.ai/DESIGN/CHATGPT_PRO_REVIEW_2026-04-18.md:115-124`, `.claude/rules/request-intake-loop.md:411-415`）。
  - Step 違反と指標悪化の対応表が部分的で、Step 1/5/6/7/8/10 がどの指標を悪化させるか不明。評価ループとしてはまだ粗い。
  - `50% 以上 pass` という目標は書かれているが、なぜ 50% が妥当かの根拠や段階目標がない。P0 制御ループの核としては弱い（`.claude/rules/request-intake-loop.md:417`）。

### R7: T-OS-154b (既存 OS 編集) への示唆の具体性
- 判定: △
- 確認内容:
  - `manager.md`, `CLAUDE.md`, `rationalization-prevention.md` に何を追加するかの方向性は明記されている（`.claude/rules/request-intake-loop.md:398-407`）。
- 問題点:
  - 提案が実装レベルまで落ちていない。たとえば `manager.md` には各 Tick で何をチェックし、どの条件で停止するか、`CLAUDE.md` にはどの既存判断フローを削除/置換するか、`rationalization-prevention.md` にはどの Red Flag を Step 違反として追加するか、まで書かれていない。

### R8: 未解決リスク
- 判定: ×
- 確認内容:
  - Step 9 で Handoff Packet と T-OS-155 への接続には触れており、subagent 文脈連携の問題意識自体はある（`.claude/rules/request-intake-loop.md:314-335`）。
- 問題点:
  - 依頼どおりの未解決リスク整理がない。毎回 10 ステップを回すコスト、緊急時 `skip_loop` フラグ、複数 subagent 間での loop 整合性が文書化されていない。
  - Step 7/9 で trace と handoff に触れているが、並列タスクで `trace_id` と `memory_updates` をどう整合させるかの規則がない（`.claude/rules/request-intake-loop.md:254-259`, `.claude/rules/request-intake-loop.md:316-320`）。

## 発見した問題 (重要度別)
### CRITICAL
- なし

### HIGH
- `.claude/rules/request-intake-loop.md:405-407` - 最高位 Iron Law でありながら、実効性を「Manager の自発的参照」に委ねている。これでは全依頼への無条件適用が保証されず、Pro 指摘の「制御システム化」が未達 - T-OS-154b で `manager.md` の Tick 先頭に Step 1-10 を固定フローとして埋め込み、未実施 Step があれば停止する enforcement を追加する。
- `.claude/rules/request-intake-loop.md:163-169` と `.claude/rules/request-intake-loop.md:194-201` - Step 5 の 4 変数分類から Step 6 のマトリクス行へ落とす還元規則がなく、`act/ask/defer/refuse` が判定不能 - `security=high` または `destructive=external` なら最低 `high`、`billing>0` なら最低 `medium` のような deterministic reduction table を追加する。
- `.claude/rules/request-intake-loop.md:409-417` - Manager Quality Eval との連動が baseline 6 指標を覆えていない。P0 評価関数として不足 - 6 指標すべてについて Step との対応表を作り、少なくとも Step 1/4/6/7/10 も指標悪化へ接続する。
- `.claude/rules/request-intake-loop.md:314-320` と `.claude/rules/request-intake-loop.md:398-407` - 未解決リスクのうち `skip_loop`、コスト制御、並列 subagent 整合性が未記載 - ループの例外運用を別節で明示し、`skip_loop` は `emergency_only + explicit trace + postmortem required` など最低限の縛りを定義する。

### MEDIUM
- `.claude/rules/request-intake-loop.md:40`, `.claude/rules/request-intake-loop.md:66`, `.claude/rules/request-intake-loop.md:75`, `.claude/rules/request-intake-loop.md:381` - `past_qa` を独立ストアのように書いており、`memory-lifecycle.md` の「fact として統一管理」と衝突する - `past_qa` ではなく `past_qa-derived facts in USER_PROFILE` に統一表現を修正する。
- `.claude/rules/request-intake-loop.md:203-220` - Active Inquiry に `max_cognitive_load` がなく、Pro の認知負荷予算モデルを完全には取り込めていない - 質問数とは別に負荷上限と、負荷超過時の分割ルールを追加する。
- `.claude/rules/request-intake-loop.md:347-359` - Coherence mode の条件が運用語で、レビュー観点としては閾値が弱い - `Full Bind` への昇格条件を `priority/order/spec/architecture changed` などに落とし、判定可能性を上げる。
- `.claude/rules/request-intake-loop.md:252-269` - `trace_id` のフォーマット、保存先、Step 5 の分類との関連付けが未定義 - `trace_id`, `decision_class`, `risk_class`, `bind_scope` の最低ログ項目を固定する。

### LOW
- `.claude/rules/request-intake-loop.md:115-117`, `.claude/rules/request-intake-loop.md:177-179`, `.claude/rules/request-intake-loop.md:267-269`, `.claude/rules/request-intake-loop.md:328-330` - 「簡略化できる」の文言が散っており、例外一覧として一箇所に集約されていない - 末尾に `Permitted Simplifications` をまとめ、各 Step はそこを参照する形にする。
- `.claude/rules/request-intake-loop.md:398-403` - T-OS-154b 向け示唆は方向性レベルで、変更差分イメージが弱い - `manager.md` 用チェックリスト、`CLAUDE.md` 用短文化文案、`rationalization-prevention.md` 用追加 Red Flag を箇条書きで付ける。

## 修正タスク候補
- `T-OS-154 FIX-001`: Step 5 → Step 6 の deterministic reduction table を追加
- `T-OS-154 FIX-002`: `manager.md` 組み込み前提の enforcement 仕様を追加し、「自発的参照」でなく強制適用に修正
- `T-OS-154 FIX-003`: baseline 6 指標と Step 1-10 の対応表を明文化し、50% 目標の中間マイルストーンも追加
- `T-OS-154 FIX-004`: `past_qa` 表現を `USER_PROFILE` fact registry ベースへ統一
- `T-OS-154 FIX-005`: Active Inquiry に `max_cognitive_load` と phase exit criteria を追加
- `T-OS-154 FIX-006`: `skip_loop`, 緊急時運用、並列 subagent 整合性、trace/memory merge 規則を未解決リスクセクションとして明記
- `T-OS-154b INPUT-001`: `manager.md` に Tick 先頭チェックリスト、未実施 Step 停止条件、microtask 時の簡略化境界を追加
- `T-OS-154b INPUT-002`: `CLAUDE.md` に Step 2-4 を通る前に質問禁止、Step 6 inquiry budget 超過禁止の短文規約を追加
- `T-OS-154b INPUT-003`: `rationalization-prevention.md` に「Request Intake Loop の 10 Step を 1 つでも欠いたら違反」を Red Flag として追加

## 検証対象
- `.claude/rules/request-intake-loop.md`
- `.claude/rules/memory-lifecycle.md`
- `.claude/rules/capability-preflight.md`
- `.claude/rules/owner-task-minimization.md`
- `.claude/rules/next-step-guidance.md`
- `.claude/rules/ai-driven-development.md`
- `.claude/rules/rationalization-prevention.md`
- `.ai/DESIGN/CHATGPT_PRO_REVIEW_2026-04-18.md`
- `.ai/CODEX/ORDERS/T-OS-154.md`
- `.ai/CODEX/RESULTS/T-OS-154.md`

## ステータス
- CHANGES_REQUESTED
