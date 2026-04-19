# Coherence Mode - deterministic 判定 rubric

> 本ルールは `.claude/rules/request-intake-loop.md` の **Step 10 (Report with Minimal Cognitive Load)** の下位ルールである。Step 3 の bind 結果を Step 10 の出力粒度へ変換するために使う。

## Iron Law

応答の Coherence mode は以下の rubric で deterministic に決定する。主観判定は禁止。

Manager は Step 3 で `CONTROL.yaml` / `TASKS.yaml` / `GOALS.yaml` を bind した結果を入力にし、Step 10 で `Silent Bind` / `Brief Bind` / `Full Bind` のいずれかを必ず選ぶ。  
`GOALS.yaml` がない場合は Step 3 未完了として扱う。micro-task 例外でも内部 bind 自体は実施する。

## Inputs

判定入力は以下に固定する:

- request text
- request word count
- `TASKS.yaml` の `status=running` task 群
- `GOALS.yaml` 由来の active milestone / active project / `active_graph`
- `DECISIONS.md` の最近 7 日の decision 参照
- Step 5 で確定した `risk_level`
- Step 6 で `ask` 判定になったか

入力が不足している場合はより低い mode に落とさず、最低でも `Full Bind` に寄せる。

## 3 段階

### Silent Bind

文脈を応答に出さない。内部 bind は実施済みであることが前提。

条件:

- 依頼が単純な読み取り、抽出、整形、一覧化などの micro-task
- 依頼文が 10 words 以下
- `TASKS.yaml` の running task と依存しない
- `GOALS.yaml` の active project / milestone と衝突しない
- 最近 7 日の decision と関連しない
- `risk_level=low`
- 応答が 3 行以下で完結する

例:

- "このログから error を抽出して"
- "JSON を整形して"

### Brief Bind

1 行だけ位置づけを書く。

条件:

- 以下のいずれかを満たす
  - 依頼が running task と関連する
  - 依頼が active milestone / active project と関連する
  - 依頼が最近 7 日の decision と関連する
  - 応答が 3-10 行になる
  - 依頼文が 11-30 words
- かつ `Full Bind` 条件を満たさない

例:

- "このファイルにログ出力追加して"
- "いまの intake loop に合わせて wording を直して"

### Full Bind

背景、影響、選択肢、推奨を明示する。

条件:

- 以下のいずれかを満たす
  - 依頼が新規方針、仕様、アーキテクチャ変更に関わる
  - Step 6 で `ask` 判定になった
  - 複数 task / project / milestone に影響する
  - `risk_level` が `medium|high|critical`
  - 最近 7 日の decision を覆す、または再解釈する
  - 依頼文が 30 words 超
  - `GOALS.yaml` / `TASKS.yaml` / decision 情報のいずれかが欠けている

例:

- "認証方式を JWT に変える"
- "デプロイ環境を AWS に移す"

## Deterministic 判定ロジック

```python
def coherence_mode(request, active_tasks, goals, recent_decisions, risk_level, decision_action):
    word_count = len(request.split())
    affects_tasks = any(keyword in request for keyword in active_tasks.keywords)
    affects_goals = any(keyword in request for keyword in goals.active_keywords)
    affects_recent_decisions = any(keyword in request for keyword in recent_decisions.keywords)
    missing_bind_inputs = (
        active_tasks is None
        or goals is None
        or recent_decisions is None
    )

    if missing_bind_inputs:
        return "Full Bind"
    if risk_level in ["medium", "high", "critical"]:
        return "Full Bind"
    if decision_action == "ask":
        return "Full Bind"
    if word_count > 30:
        return "Full Bind"
    if affects_recent_decisions and not (affects_tasks or affects_goals):
        return "Full Bind"
    if affects_tasks or affects_goals or affects_recent_decisions:
        return "Brief Bind"
    if 11 <= word_count <= 30:
        return "Brief Bind"
    return "Silent Bind"
```

優先順は `Full Bind > Brief Bind > Silent Bind`。複数条件に一致した場合は常に上位 mode を採用する。

## Output Contract

各 mode の最小出力要件:

- `Silent Bind`: 依頼結果のみ。文脈説明は書かない。
- `Brief Bind`: 先頭 1 行で「この依頼が何に紐づくか」だけを示す。
- `Full Bind`: 背景、影響、選択肢、推奨を明示してから結論を述べる。

`Brief Bind` の 1 行は以下のような形に固定する:

```text
[Context] This request maps to <running task / milestone / decision> and is being handled within that scope.
```

`Full Bind` では最低限以下を含める:

1. Background
2. Impact
3. Options
4. Recommendation

## GOALS.yaml 参照ルール

`GOALS.yaml` は Step 3 の mandatory input であり、以下の 3 点に使う:

- 依頼がどの milestone / project に属するかを判定する
- active milestone と矛盾する提案を防ぐ
- Step 10 でどの程度 bind を表出すべきかの材料にする

既存の `memory-lifecycle.md` や `request-intake-loop.md` への直接追記は別タスクで扱う。本タスクでは本ルールを SSOT として追加する。

## active_graph 自動更新設計

`GOALS.yaml.active_graph` は毎 Tick 更新する。実装は別タスクとし、ここでは `scripts/goals/update-active-graph.sh` の設計だけ定義する。

### Script Contract

- path: `scripts/goals/update-active-graph.sh`
- inputs:
  - `.ai/CONTROL.yaml`
  - `.ai/TASKS.yaml`
  - `.ai/DECISIONS.md`
  - `.ai/GOALS.yaml`
- outputs:
  - `.ai/GOALS.yaml.active_graph` を in-place 更新
- update cadence:
  - Manager Tick の Step 3 直前または Step 3 冒頭

### Required Behavior

1. `CONTROL.yaml` から `current_phase` を解決する。
2. `TASKS.yaml` から `status=running` を `running_tasks` に、`status=blocked` を `blocked_tasks` に反映する。
3. `DECISIONS.md` から最新 5 件の decision reference を抽出し、`recent_decisions` に書く。
4. `GOALS.yaml.projects[*].status` は task 状態から自動上書きしない。明示更新がない限り保持する。
5. secrets や PII を書き込まない。
6. schema にない key を追加しない。

### Pseudocode

```bash
#!/usr/bin/env bash
set -euo pipefail

# 1. read current phase from CONTROL.yaml
# 2. collect running / blocked task ids from TASKS.yaml
# 3. extract last 5 decision references from DECISIONS.md
# 4. rewrite only active_graph in GOALS.yaml
# 5. fail if output would introduce non-schema keys or secret-like values
```

## 違反検出

- 全応答に mode 判定ログを trace と `handoff-packet.verification.self_check` へ記録する
- `context_miss_rate` と `unnecessary_owner_question_rate` で誤判定を検出する
- `Silent Bind` なのに running task と衝突していた場合は violation
- `Brief Bind` なのに 1 行の bind 説明がない場合は violation
- `Full Bind` 条件を満たすのに背景 / 影響 / 推奨が欠けている場合は violation

## Red Flags

以下を検出したら低い mode を選ばず `Full Bind` に上げる:

- 依頼が active milestone に影響するのに `Silent Bind` を選ぼうとしている
- `GOALS.yaml` 不在または parse failure のまま応答しようとしている
- decision 参照不足のまま方針変更を説明しようとしている
- risk classification 未確定のまま実装提案に入ろうとしている
