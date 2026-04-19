# Handoff Protocol

> OrgOS の subagent / Codex worker は、完了時に必ず Handoff Packet を返却する。例外なし。

## Purpose

- 成果物だけでなく、仮定、未解決点、下流影響、記憶更新候補、検証結果を機械可読で引き渡す
- 並列タスクでも trace metadata により文脈を再構成可能にする
- Request Intake Loop Step 9 で handoff を安全に機械処理可能にする

## Iron Law

全 subagent / Codex worker は、完了・保留・差し戻しを問わず `.claude/schemas/handoff-packet.yaml` に準拠した `handoff_packet` を返却しなければならない。成果物だけを返して処理を閉じてはならない。例外なし。

最低限、以下は必須である:

- `schema_version`
- `task_id`
- `agent`
- `status`
- `completed_at`
- `trace`
- `changed_files`
- `assumptions`
- `decisions_made`
- `unresolved_questions`
- `downstream_impacts`
- `memory_updates`
- `verification`

## Required Status Semantics

- `DONE`: 受入条件を満たし、未解決点が完了判定を妨げない
- `DONE_WITH_CONCERNS`: 完了したが、下流タスクや Manager が追うべき懸念がある
- `NEEDS_CONTEXT`: packet 不完全、または追加文脈なしに妥当な完了報告ができない
- `BLOCKED`: 依存・権限・情報欠落により進行不能
- `CHANGES_REQUESTED`: レビューまたは再作業指示が必要

## Sender Contract

subagent は packet 作成時に以下を守る:

1. `schema_version` は必ず `"1.0"` を返す
2. `changed_files` には実際に変更したファイルだけを入れる
3. `assumptions` は暗黙判断を隠さず明記する
4. `decisions_made` には採用した判断と、捨てた代替案を残す
5. `unresolved_questions` は blocker かどうかを明示する
6. `downstream_impacts` は影響先タスクを `T-OS-XXX` 形式で特定する
7. `memory_updates` は target / operation / scope / payload を schema の oneOf に一致させる
8. `verification` には tests / eval / self-check を残し、自己申告だけで完了扱いしない

## Packet 欠損時の対応

packet が存在しない、または必須フィールドが欠ける場合、その handoff は有効完了として扱わない。Manager は以下の順序で処理する:

1. 当該報告を `NEEDS_CONTEXT` とみなす
2. 不足フィールドを特定し、subagent に再送要求する
3. 再送を待つ間、Step 9 の状態更新は保留する
4. retry policy に従って再送の可否を判定する

## Manager Receive / Apply Logic

Manager は packet 受信時に以下を行う:

1. schema 準拠を検証する
2. `trace.request_trace_id` で同一依頼系統の packet をグルーピングする
3. `trace.span_id` / `trace.parent_span_id` / `trace.resume_of` で handoff chain を復元する
4. `status` に応じて完了、懸念付き完了、文脈不足、ブロック、差し戻しを分岐する
5. `changed_files` を成果物索引として保持する
6. `assumptions` と `decisions_made` を decision trace に編入する
7. `unresolved_questions` を次アクションへ移送する
8. `downstream_impacts` と `memory_updates` を Step 9 で反映または quarantine する
9. `verification` を Quality Eval 入力として保持する

## Request Intake Loop との統合

`request-intake-loop.md` Step 9 (Update TASKS / DECISIONS / MEMORY) で:

1. subagent 完了報告を受信
2. Handoff Packet を schema に従って parse
3. `memory_updates` を target ごとに validate する
4. validation success の更新のみ適用候補に進める
5. validation failure の更新は quarantine に送る
6. `downstream_impacts` を `TASKS.yaml` の対象タスクに反映する
7. `unresolved_questions` を Active Inquiry の次の turn に引き継ぐ
8. `verification` を Manager Quality Eval の `decision_trace_completeness` 計算に使用する

`memory_updates` の適用ルール:

- `target=USER_PROFILE.facts`: `memory-lifecycle.md` の `capture` / `update` / `retire` / `promote` に従って反映する。payload は fact schema に一致しなければならない。
- `target=USER_PROFILE.preferences`: `memory-lifecycle.md` の同一 lifecycle に従って反映する。payload は preference schema に一致しなければならない。
- `target=CAPABILITIES`: `operation=update` のみ許可し、payload の `capability_id` と `fields_to_update` を validate した後に `scan.sh` を trigger して再生成 + merge する。
- `target=DECISIONS`: `operation=append` のみ許可し、payload の `decision_id` と `content` を validate した後に decision ledger へ append する。

validation failure 時の動作:

- shared state には apply しない
- packet または該当 update を quarantine に一時格納する
- Manager review で `apply` または `discard` を決定する
- quarantine 中の update は自動反映しない

## Scope Registry

`memory_updates.scope` と、payload 内で scope を持つ対象は以下の registry に一致しなければならない。

- `user_profile.facts.working`
- `user_profile.facts.confirmed`
- `user_profile.facts.deprecated`
- `user_profile.preferences.working`
- `user_profile.preferences.confirmed`
- `user_profile.preferences.deprecated`
- `capabilities.registry`
- `decisions.ledger`

未登録 scope は protocol violation とし、validation failure 扱いで quarantine する。

## Trace Model

Manager は request 単位と実行 span 単位を分離して追跡する。

- `trace.request_trace_id`: 依頼単位の最上位 ID。request intake で発行し、同一依頼の全 packet で共有する。
- `trace.span_id`: 個別 subagent 実行 span。subagent 起動ごと、または retry ごとに新規発行する。
- `trace.attempt`: retry 番号。初回は `1`。
- `trace.parent_span_id`: 親 span。handoff chain の親子関係を復元する。
- `trace.resume_of`: durable execution で再開した元 span。resume でない場合は `null`。

運用ルール:

- `request_trace_id` は request-level grouping にのみ使う
- retry は同じ `request_trace_id` を維持しつつ `span_id` または `attempt` を更新する
- durable resume は `resume_of` で明示する
- packet の idempotency 判定は `request_trace_id + span_id + attempt` の組で行う

## Trace Mapping Reference

OpenAI Agents SDK / LangGraph との対応は以下を基準とする。

- OpenAI Agents SDK の trace/run 相当: `trace.request_trace_id`
- OpenAI Agents SDK の span 相当: `trace.span_id`
- OpenAI Agents SDK の retry metadata 相当: `trace.attempt`
- LangGraph の span tree / edge 相当: `trace.parent_span_id`
- LangGraph の durable resume checkpoint 相当: `trace.resume_of`

この対応表は tracing 実装を固定するものではなく、将来の execution metadata 拡張の基準点として扱う。

## Retry Policy

`retry_policy`:

```yaml
retry_policy:
  max_attempts: 3
  backoff:
    - attempt_1: 0s
    - attempt_2: 30s
    - attempt_3: 120s
  stop_conditions:
    - status: BLOCKED
    - 3回全て packet 不完全
  escalation:
    - 3回失敗時は DECISIONS.md に ISSUE-HPKT-XXX として記録
    - Owner への escalation は Iron Law 違反レベルの緊急時のみ
  partial_salvage:
    - packet 不完全でも changed_files と verification が揃っていれば部分適用を検討
```

状態遷移ルール:

- `status=BLOCKED` は即停止し、retry しない
- packet 不完全で `max_attempts` に達するまでは backoff に従って再送を試みる
- 3 回全て packet 不完全なら、対象 subagent を quarantine 扱いにし、その packet 系列を自動適用しない
- 3 回失敗時は `DECISIONS.md` に `ISSUE-HPKT-XXX` として記録する
- Owner への escalation は Iron Law 違反や安全性事故など緊急時のみ許可する
- `changed_files` と `verification` が揃っている場合のみ、Manager は partial salvage を検討できる

## Backward Compatibility

既存の `.ai/CODEX/RESULTS/*.md` は非構造化 Markdown である。新 protocol では以下を許可する:

- Option A: YAML frontmatter + Markdown 本文
- Option B: Markdown 末尾に `yaml handoff_packet` fenced block

`legacy_result_fallback`:

```yaml
legacy_result_fallback:
  detection: "packet missing or schema_version absent"
  behavior: "parse best-effort from Markdown, extract Status/Changed Files/Notes"
  migration_sunset: "2026-06-01 以降は legacy_result を reject"
```

運用ルール:

- parser は packet が存在すれば packet を優先する
- packet がなく、または `schema_version` が欠落していれば legacy_result fallback を起動する
- fallback では最低限 `Status` / `Changed Files` / `Notes` を best-effort 抽出する
- `2026-06-01` 以降は packet 非搭載の legacy_result を reject する

## Iron Law 違反検出

以下は本 protocol の違反である:

- packet 欠損
- 必須フィールド未埋め
- `schema_version` 欠損または未対応バージョン
- `status` が enum 外
- `trace.request_trace_id` / `trace.span_id` / `trace.attempt` 欠損
- `memory_updates.scope` が未登録
- `memory_updates` が target 別 oneOf schema に一致しない

machine-readable violation 条件:

- `empty_array_prohibited: [assumptions, decisions_made]`
- `evidence_required: verification.tests_run or verification.eval_results is non-empty for non-trivial tasks`

lint script 仕様メモ:

- lint は上記 violation 条件を deterministic に判定する
- non-trivial task 判定基準と partial salvage は T-OS-155G 以降で実装する
- 本ファイルは lint が実装すべき仕様を定義する

Manager の対応:

- packet 不完全または schema violation → subagent に再送要求し、`NEEDS_CONTEXT` として扱う
- validation failure を伴う `memory_updates` → quarantine に送る
- 3 回連続で packet 不完全 → subagent の問題として記録し、自動適用を停止する

## Review / Audit Expectations

- `assumptions` が空でも、暗黙仮定が存在するなら packet 不備とみなす
- `decisions_made` が空でも、実際に判断を行っていれば packet 不備とみなす
- `verification.tests_run` が空の場合、`verification.eval_results` が非空であるか、未テスト理由を `verification.self_check` に残す
- `downstream_impacts` を省略してよいのは、本当に下流影響がない場合のみ
- `memory_updates` を省略してよいのは、再利用価値のある新情報が存在しない場合のみ

## T-OS-155b で実施予定

以下の既存ファイルへの Handoff Packet 返却強制の組み込みは本タスクでは実施しない:

- `.claude/agents/manager.md`: Manager 側の packet 受信ロジックと parser 優先順位
- `.claude/agents/{org-planner, org-architect, org-reviewer, ...}.md`: 各 subagent の packet 返却義務と fail-fast 文言
- `.claude/agents/CODEX_WORKER_GUIDE.md`: Codex worker の packet 返却強制と legacy_result からの移行

retrofit 時の最低要件:

- agent prompt に packet 返却義務、`schema_version`、trace fields、retry 時の attempt 更新を追記する
- packet 未返却時は fail-fast して `NEEDS_CONTEXT` を返す
- parser は packet 優先、fallback 次点、複数 packet 混在時は最新 `completed_at` を優先する
