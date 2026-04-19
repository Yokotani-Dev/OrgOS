# Cross-Session Consistency — Iron Law

> 本ルールは `.claude/rules/request-intake-loop.md` の **Step 3 (Bind Active Work Graph)** の実装詳細である。単発依頼を既存 Work Graph に結び付けずに処理することを禁止する。

## Purpose

- 単発依頼でも進行中 task / active milestone / recent decisions との整合を強制する
- Owner の「他のタスクと整合が取れない」を deterministic に防ぐ
- `context_miss_rate` を Step 3 実施有無で評価可能にする

## Iron Law

依頼を受けたら応答前に必ず以下を実行する。例外なし。

1. `bash scripts/session/bind-request.sh` で依頼内容と既存 Work Graph を照合する
2. バインド結果を次の 3 カテゴリに分類する
   - `task_continuation`: 進行中 `running` / `review` task の延長
   - `sub_task_of_active_project`: 進行中 milestone / project の新規子タスク
   - `new_project`: 既存とは独立。Owner 確認推奨
3. 応答冒頭で `response_prefix` をそのまま、または同等の意味で `【文脈】...` 形式で明示する
4. 必要なら `TASKS.yaml` 更新を提案する。ただし更新自体は Manager 権限で行う

## Required Inputs

- `.ai/TASKS.yaml`
  - `running` / `review` / `queued` task の title / notes / acceptance
- `.ai/GOALS.yaml`
  - `active` milestone / project
- `.ai/DECISIONS.md`
  - 直近の決定と recent mentions

## Bind Procedure

### Step 1. Normalize Request

- 依頼原文をそのまま保持する
- `T-OS-180` や `M-PHASE-3` のような ID を優先抽出する
- 日本語句、英単語、数値トークンを正規化する

### Step 2. Score Against Active Work Graph

- task title / notes / acceptance と keyword 一致を取る
- semantic 類似は簡易実装でよい
  - 共通単語数
  - ID 直接一致
  - phrase 部分一致
- decision は最近のものを優先し、recent mention を加点する

### Step 3. Classify

- `task_continuation`
  - `running` または `review` task に対し score `>= 0.7`
- `sub_task_of_active_project`
  - task / milestone / project に対し score `>= 0.3`
  - continuation 条件は満たさない
- `new_project`
  - 既存 graph に十分な一致がない

### Step 4. Emit Response Prefix

出力 JSON の `response_prefix` を応答冒頭に反映する。

例:

- `task_continuation`: `【文脈】T-OS-XXX (running) の延長として処理します`
- `sub_task_of_active_project`: `【文脈】M-XXX milestone 配下の新規タスクとして提案します`
- `new_project`: `【文脈】既存タスクとは独立。新規プロジェクト化を推奨`

## 判定ロジック

- keyword 一致
  - task title / notes / acceptance
  - milestone / project title / description
  - recent decision title / body
- semantic 類似
  - 共通単語数
  - Jaccard 相当
  - ID 一致ブースト
- 参照関係
  - `DECISIONS.md` の最近言及を加点

## Suggested Actions

- `task_continuation` -> `bind`
- `sub_task_of_active_project` -> `propose_sub_task`
- `new_project` -> `confirm_new_project`

## Manager Execution Contract

Manager は Step 3 の実行時に次を順守する。

1. `bind-request.sh` に依頼原文を渡す
2. `classification`, `related_tasks`, `related_milestones`, `related_decisions` を確認する
3. `response_prefix` を Step 10 の report に反映する
4. `suggested_action=propose_sub_task` なら `TASKS.yaml` 更新提案を先に示す

## Red Flags

- 単発依頼を進行中プロジェクト無視で処理する
- バインド結果を応答で明示しない
- `new_project` 相当なのに既存 task continuation のように扱う
- decision / milestone と衝突しているのに整合確認を省略する

## Manager Quality Eval Link

`context_miss_rate` は本ルールの遵守に直結する。

- `bind-request.sh` の出力を応答に含めた -> pass
- bind を無視して処理した -> fail

## Relationship To Other Rules

- `.claude/rules/request-intake-loop.md`
  - Step 3 の下位ルール
- `.claude/rules/session-bootstrap.md`
  - bootstrap 後に本ルールを必ず適用する
- `.claude/rules/coherence-mode.md`
  - Step 3 の bind 結果を Step 10 でどこまで表出するかを決める

## Bootstrap Integration Note

`session-bootstrap.md` への参照リンク追加方針は `T-OS-180b` で扱う。本タスクでは編集しないが、bootstrap 後の依頼受付で本ルールを Step 3 実装詳細として参照する前提を固定する。
