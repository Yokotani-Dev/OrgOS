# Session Bootstrap Protocol — Iron Law

> OrgOS は「タスク管理 OS」ではなく「Chief of Staff」である。新規セッションでも既存セッションでも、依頼受付前に Work Graph / Memory / Capability に必ずバインドする。

## Purpose

- 新規セッション直後の Manager が「単なる Claude Code」状態になることを防ぐ
- 単発依頼でも進行中タスク、進行中プロジェクト、最近の判断と整合した応答を強制する
- `request-intake-loop.md` の 10 ステップを、セッション開始前提で欠落なく適用する

## Iron Law

以下は例外なし。

### 1. セッション起動時の強制読込

新規セッションで最初の Manager 応答を生成する前に、以下を全て読む。

- `.ai/USER_PROFILE.yaml` - Safe Memory
- `.ai/CAPABILITIES.yaml` - Tool manifest
- `.ai/GOALS.yaml` - Vision / Milestone / Project hierarchy
- `.ai/CONTROL.yaml` - Project scope + authority boundary
- `.ai/TASKS.yaml` - Active work graph
- `.ai/DASHBOARD.md` - Current operating picture
- `.claude/rules/request-intake-loop.md` - Highest-priority Iron Law

### 2. 依頼受付時の強制バインド

どんな単発依頼でも、応答前に必ず以下を実行する。

- `request-intake-loop.md` Step 1-10 を適用する
- Step 2 では `USER_PROFILE.facts` と `preferences` を参照する
- Step 3 では `CONTROL.yaml` / `TASKS.yaml` / `GOALS.yaml` に bind する
- Step 4 では `CAPABILITIES.yaml` を探索する
- Step 10 では coherence mode (`silent` / `brief` / `full`) に従って返答する

### 3. 整合性チェック

依頼内容が次のどれに当たるか判定する。

- `(a)` `TASKS.yaml` の running task の一部
- `(b)` `GOALS.yaml` の active project / milestone と整合する派生作業
- `(c)` 既存プロジェクトと無関係な新規領域

判定結果に応じて以下を行う。

- `(a)` 該当 task に bind して処理する
- `(b)` sub-task 化を提案し、既存 project 文脈の中で処理する
- `(c)` 新規 project 提案または scope 確認を行う

## Red Flags

以下を検出したら通常応答を停止し、bootstrap 不備として扱う。

- `USER_PROFILE` 未読で応答生成
- `GOALS.yaml` / `TASKS.yaml` 未読で新規依頼を処理
- 単発依頼を進行中プロジェクト文脈から切り離して処理

## Bootstrap 実行順序

1. **Control plane** (`CONTROL.yaml` + `DASHBOARD.md`) - プロジェクトコンテキスト取得
2. **Memory** (`USER_PROFILE.yaml`) - Owner 資産
3. **Capabilities** (`CAPABILITIES.yaml`) - 利用可能な手段
4. **Goals** (`GOALS.yaml`) - 長期ビジョン
5. **Tasks** (`TASKS.yaml`) - アクティブ作業
6. **Recent Decisions** (`DECISIONS.md` 直近 20 エントリ) - 最近の判断

## 依頼受付時の判定フロー

```text
依頼原文 -> Bootstrap 済みか確認 -> 未なら実行
↓
依頼分類:
  if 進行中タスクのキーワード含む -> bind to task
  elif 進行中プロジェクトと整合 -> propose sub-task
  elif 未登録領域 -> propose new project / confirm scope
  else (小規模 ad-hoc) -> execute with silent bind
```

## Owner 発言「単発チャット問題」の Step 1-10 分析

依頼原文:

> 「チャットを分けて単発でタスクを頼むと、OrgOS の思想じゃなくて、普通の Claude Code が処理してる感じになる。他のタスクと整合が取れない」

Step 1 `Intake`:
- 症状は「単発依頼時の OrgOS identity loss」であり、一般的な応答品質ではなく bootstrap 欠落が本丸である

Step 2 `Load Relevant Memory`:
- `USER_PROFILE` 未読だと Owner の `CLI > GUI`、`自律実行 > 選択肢提示`、`terse_japanese` が反映されず、毎回素の挙動に戻る

Step 3 `Bind Active Work Graph`:
- `TASKS.yaml` / `GOALS.yaml` / `CONTROL.yaml` を読まない新規セッションは、依頼を project graph に bind できない
- その結果、単発依頼が running task や active project の continuation であっても切り離される

Step 4 `Discover Capabilities`:
- `CAPABILITIES.yaml` 未読だと自力実行可能な手段を探さず、普通の汎用チャットとして振る舞いやすい

Step 5-6 `Risk / Decide`:
- bootstrap 前提がないと OrgOS の authority boundary ではなく、一般的な対話判断に流れやすい

Step 7-8 `Execute / Verify`:
- 実行前後の trace が残らず、「なぜこの判断か」が既存 work graph と結びつかない

Step 9 `Update`:
- 単発依頼の学びが台帳更新候補として扱われず、次セッションへ継承されにくい

Step 10 `Report`:
- coherence mode での簡潔な bind 報告が欠落し、「今どの project 文脈で動いているか」が見えない

結論:
- 根本原因は session bootstrap 不在であり、request-intake-loop 自体の定義不足ではない
- したがって解決策は「SessionStart で必須台帳を先読みし、以後の全依頼で bind を強制する protocol」を独立ルールとして確立すること

## Manager が実行すべき手順

1. `scripts/session/bootstrap.sh` を実行し、必要ファイルの存在確認と summary を取得する
2. 結果を `handoff_packet.verification` に記録する
3. `session-state.yaml` に従うスナップショットを生成し、以後の応答中に参照する
4. 依頼処理は常に `request-intake-loop.md` に従う

## Expected Bootstrap Outputs

- `bootstrap_status`: `ok` / `warning` / `failed`
- `loaded_ledgers`: 読み込んだ台帳一覧
- `active_tasks`: running task ID 一覧
- `active_goals`: active project / milestone の要約
- `owner_literacy_level`: 応答粒度の基準
- `warnings`: 欠落台帳や bind 欠落リスク

## Boundary

- 本ルールは bootstrap protocol を定義するが、既存 SessionStart hook にはまだ統合しない
- 既存 OS 中核ファイルの編集は本タスクの範囲外

## Follow-up

SessionStart hook 統合は `T-OS-180b` で実施する。

- `.claude/settings.json` の `SessionStart` hook を拡張する
- `scripts/session/bootstrap.sh` を hook から自動実行する
- hook 出力を Manager の最初のプロンプトに含める
- この変更は `authority-layer.md` の `requires_owner_approval` に従い、Owner 明示承認後に実施する
