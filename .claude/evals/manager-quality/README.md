# Manager Quality Eval

ChatGPT Pro review (`.ai/DESIGN/CHATGPT_PRO_REVIEW_2026-04-18.md`) で最大の盲点とされた「Manager の評価関数がない」を埋める regression suite です。目的は、Owner の実不満から導出した 20 ケースを固定化し、Phase 1 以降の改善が `repeated_question_rate` / `context_miss_rate` を本当に下げているかを継続測定することです。

## 使い方

```bash
.claude/evals/manager-quality/run.sh
.claude/evals/manager-quality/run.sh --json
scripts/eval/manager-quality-runner.sh
scripts/eval/generate-regression-report.sh
scripts/eval/generate-regression-report.sh --last 2
scripts/eval/generate-regression-report.sh --date 2026-04-18
scripts/eval/trend-calculator.sh
```

- 実行結果は `.ai/METRICS/manager-quality/YYYY-MM-DD.jsonl` に 1 case = 1 line で追記されます。
- `report.py selftest --repo-root <repo>` で category ごとの期待 pass/fail スナップショットを検証できます。
- P0 指標 (`repeated_question_rate`, `context_miss_rate`) が target を満たさない場合、suite は exit code `1` を返します。
- regression 検知は `.ai/METRICS/manager-quality/regression-YYYY-MM-DD.md` に payload を出力し、退行があれば exit code `2` を返します。
- `scripts/eval/trend-calculator.sh` は `owner_requests / total_tasks` の日次比率から 3 日 / 7 日 moving average を計算し、3 日未満なら `pending` を返します。

## Judge 実装状況

| Category | Cases | Runtime Source | Judge Status | 備考 |
|---|---:|---|---|---|
| repeated_question | 4 | `USER_PROFILE.yaml` | real | T-OS-151F 実装 |
| cli_over_gui | 4 | `CAPABILITIES.yaml` | real | `status` / `auth_status` / `common_operations` を参照 |
| context_miss | 4 | `TASKS.yaml` / `CONTROL.yaml` / `DECISIONS.md` / `GOALS.yaml` | real | `GOALS.yaml` 不在時は fail-safe reason を返す |
| unnecessary_question | 3 | `USER_PROFILE.yaml` / `CAPABILITIES.yaml` | real | Active Inquiry 条件も参照 |
| capability_reuse | 3 | `CAPABILITIES.yaml` | real | 未登録 capability は reuse 不可として fail |
| decision_trace | 2 | `Handoff Packet` / `USER_PROFILE.yaml` | real | Handoff Packet があれば rubric 監査、未実装タスクは legacy fallback |

## Mock To Real Migration

| Category | Before | Now |
|---|---|---|
| repeated_question | real | real |
| cli_over_gui | mock fail 固定 | real judge |
| context_miss | mock fail 固定 | real judge |
| unnecessary_question | mock fail 固定 | real judge |
| capability_reuse | mock fail 固定 | real judge |
| decision_trace | real | real |

## ケース一覧

| # | ID | Category | Metric | 症状 | 要旨 |
|---|---|---|---|---|---|
| 01 | MQ-001 | repeated_question | repeated_question_rate | A | 既知の `project_ref` を再質問しない |
| 02 | MQ-002 | repeated_question | repeated_question_rate | A | 過去に共有済みの GitHub org を再質問しない |
| 03 | MQ-003 | repeated_question | repeated_question_rate | A | 既知の Vercel team を再質問しない |
| 04 | MQ-004 | repeated_question | repeated_question_rate | A | 過去に確定した deploy 手順を再確認しない |
| 05 | MQ-005 | cli_over_gui | owner_delegation_burden | A | GUI 依頼ではなく `gh` で PR 情報取得 |
| 06 | MQ-006 | cli_over_gui | owner_delegation_burden | A | Supabase 設定を CLI で解決 |
| 07 | MQ-007 | cli_over_gui | owner_delegation_burden | A | Vercel env 確認を UI 依頼に逃がさない |
| 08 | MQ-008 | cli_over_gui | owner_delegation_burden | A | Stripe 設定を dashboard 作業へ丸投げしない |
| 09 | MQ-009 | context_miss | context_miss_rate | B | 単発依頼でも進行中 task graph に bind |
| 10 | MQ-010 | context_miss | context_miss_rate | B | 並列タスクの成果を見落とさない |
| 11 | MQ-011 | context_miss | context_miss_rate | B | 現フェーズと依頼の位置づけを外さない |
| 12 | MQ-012 | context_miss | context_miss_rate | B | 直近 Decision を無視した提案をしない |
| 13 | MQ-013 | unnecessary_question | unnecessary_owner_question_rate | C | リポジトリ内検索で済む質問をしない |
| 14 | MQ-014 | unnecessary_question | unnecessary_owner_question_rate | C | CLI で取得できる build 情報を聞かない |
| 15 | MQ-015 | unnecessary_question | unnecessary_owner_question_rate | C | low-risk 仮定で進められる確認を聞かない |
| 16 | MQ-016 | capability_reuse | capability_reuse_rate | A/B | 既知の `gh` capability を再利用する |
| 17 | MQ-017 | capability_reuse | capability_reuse_rate | A/B | 既存 script を再利用する |
| 18 | MQ-018 | capability_reuse | capability_reuse_rate | A/B | MCP/CLI 既知手段を優先する |
| 19 | MQ-019 | decision_trace | decision_trace_completeness | trace | 判断理由と根拠を残す |
| 20 | MQ-020 | decision_trace | decision_trace_completeness | trace | handoff packet 相当の trace を残す |

## 指標と判定

| Metric | Target | Priority | 判定 |
|---|---|---|---|
| repeated_question_rate | `< 5%` | P0 | 失敗ケース比率が 5% 未満 |
| context_miss_rate | `< 3%` | P0 | 失敗ケース比率が 3% 未満 |
| unnecessary_owner_question_rate | `< 10%` | P1 | 失敗ケース比率が 10% 未満 |
| capability_reuse_rate | `> 80%` | P1 | 成功ケース比率が 80% 超 |
| owner_delegation_burden | `downward trend` | P1 | 直近 7 日の日次比率から 3d MA と 7d MA を比較。3 日未満は `pending` |
| decision_trace_completeness | `> 95%` | P0 | Handoff Packet rubric 監査で full trace 率を算出。legacy task は除外可 |

## Regression Detection

`scripts/eval/generate-regression-report.sh` は最新 run を基準に比較します。

- デフォルト: 直前の run と比較
- `--last N`: 最新 run と直近 N 件の過去 run を比較
- `--date YYYY-MM-DD`: 最新 run と指定日の最新 run を比較

検出内容:

- 前回 pass → 今回 fail のケース
- 前回 target 達成 → 今回未達の metric

退行があった場合は exit code `2` を返します。P0 fail の exit code `1` とは分離しています。

## Decision Trace Rubric

`decision_trace_completeness` は Handoff Packet を優先入力として監査します。full trace 条件は次の 5 つです。

- `assumptions` が 1 件以上、または `no assumptions` の明示
- `decisions_made` が 1 件以上あり、`rationale` と `alternatives_considered` が埋まっている
- `verification.tests_run` または `verification.eval_results` が非空
- `memory_updates` が 1 件以上、または `no updates` の明示
- `trace.request_trace_id` と `trace.span_id` が存在する

機械可読な packet がない legacy task は denominator から除外できます。packet が見つからない間は既存の trace metadata fallback で判定を継続します。

## 新ケース追加

1. `cases/NN-name.yaml` を追加する。
2. `id`, `title`, `category`, `symptom`, `scenario`, `input`, `expected_behavior`, `anti_pattern`, `metric`, `weight` を埋める。
3. `metric` は `metrics.yaml` に定義済みの id を使う。
4. `run.sh` を再実行して `.ai/METRICS/manager-quality/*.jsonl` に記録する。
5. 退行検知対象にしたい場合は `scripts/eval/generate-regression-report.sh` で前回 run と比較する。
