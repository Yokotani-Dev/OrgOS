# T-OS-154b Result

## Status

DONE

## Summary

`manager.md` の Tick フローを `.claude/rules/request-intake-loop.md` Step 1-10 に統合し、旧 Tick Step 1-6/7 の責務を 10 ステップへ再マッピングした。

`CLAUDE.md` は最小差分で、最高位 Iron Law と新規 3 ルールへの参照を「守るべきこと」テーブルの先頭へ追加した。

## Files Changed

- `.claude/agents/manager.md`
- `CLAUDE.md`
- `.ai/CODEX/RESULTS/T-OS-154b.md`

## Backups

- `.claude/agents/manager.md` backup: `.ai/BACKUPS/manager.md.2026-04-19.bak`
- `CLAUDE.md` backup: `.ai/BACKUPS/CLAUDE.md.2026-04-19.bak`

## Diff Summary

### `.claude/agents/manager.md`

Added:
- Tick は `.claude/rules/request-intake-loop.md` Step 1-10 そのものとして扱う旨
- Tick 先頭の Iron Law:
  - `bash scripts/session/bootstrap.sh` を未実行なら実行
  - `.ai/USER_PROFILE.yaml` 参照
  - `.ai/CAPABILITIES.yaml` 参照
  - `.ai/TASKS.yaml` / `.ai/GOALS.yaml` / `.ai/DECISIONS.md` への Work Graph bind
  - Request Intake Loop Step 1-10 の応答前実施
- 旧 Tick フロー対応表:
  - 旧 Step 1 状況把握 -> Step 3 Bind Active Work Graph
  - 旧 Step 2 ブロッカー確認 -> Step 5-6 Risk / Decide
  - 旧 Step 3 タスク選択 -> Step 3 + Step 6
  - 旧 Step 4 エージェント起動 -> Step 4 + Step 7
  - 旧 Step 5 結果反映 -> Step 8-9
  - 旧 Step 5.5 MVP 確認 -> Step 5-6 + Step 10
  - 旧 Step 6 計画整合性チェック -> Step 8-9
  - 旧 Step 7 報告と次の実行 -> Step 10
- Request Intake Loop Step 1-10 の各見出しと Manager 向け実行内容

Maintained:
- エージェント起動テーブル
- allowed_paths 衝突防止の考え方
- P0/P1/P2/P3 優先度
- MVP -> 確認 -> 拡張サイクル
- 台帳更新対象
- plan-sync / next-step-guidance 参照
- Codex 起動ロジック、ゴール管理、literacy adaptation 周辺の既存記述

Removed/Rewritten:
- 旧 Tick Step 1-6/7 の独立フローを削除し、Request Intake Loop Step 1-10 内の責務として再配置した。

### `CLAUDE.md`

Added:
- 「最優先ルール」冒頭:
  - `**最高位 Iron Law**: 全依頼は .claude/rules/request-intake-loop.md の 10 ステップを適用する。例外なし。`
- 「守るべきこと」テーブル先頭:
  - `.claude/rules/request-intake-loop.md`
  - `.claude/rules/session-bootstrap.md`
  - `.claude/rules/authority-layer.md`

Maintained:
- 既存の Manager 仕様、project-flow、session-management、next-step-guidance、plan-sync、literacy adaptation などの参照
- OrgOS フロー優先、Codex 起動、計画同期、自律実行の既存記述

## Verification

### Manager Quality Eval

Command:

```bash
bash .claude/evals/manager-quality/run.sh --json
```

Result:

- passed: 19/20
- failed: 1/20
- critical_failure: false
- target: 19/20 以上を維持
- status: pass

Metric highlights:

- repeated_question_rate: 0.0%, target met
- context_miss_rate: 0.0%, target met
- unnecessary_owner_question_rate: 0.0%, target met
- capability_reuse_rate: 100.0%, target met
- owner_delegation_burden: 5.0%, target met
- decision_trace_completeness: 100.0%, target met

### Regression Report

Command:

```bash
bash scripts/eval/generate-regression-report.sh --json
```

Latest result:

- status: stable
- baseline_run_ids: `2026-04-18T15:56:19+00:00`
- current_run_id: `2026-04-19T05:30:37+00:00`
- regressions: none
- metric_regressions: none
- payload_path: `.ai/METRICS/manager-quality/regression-2026-04-19.md`

## Rollback

Restore from backups:

```bash
cp .ai/BACKUPS/manager.md.2026-04-19.bak .claude/agents/manager.md
cp .ai/BACKUPS/CLAUDE.md.2026-04-19.bak CLAUDE.md
```

Then rerun verification:

```bash
bash .claude/evals/manager-quality/run.sh --json
bash scripts/eval/generate-regression-report.sh --json
```

## Notes

- Owner Authorization: `[A] 全部進める` (2026-04-19 朝)
- AGENTS.md の通常 OS 改修禁止事項は、Work Order の Owner 明示承認と allowed_paths に基づいて例外扱い。
