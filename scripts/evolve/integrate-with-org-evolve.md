# Daily Check Integration Memo

## Scope

This memo defines how daily self-improvement signals should feed weekly `org-evolve` without changing the current weekly workflow in `T-OS-183`.

## Role Split

### Daily `daily-health-check`

- Run every day and produce a lightweight operating baseline.
- Execute:
  - Manager Quality eval
  - regression detection
  - capabilities scan
  - memory normalize / promote lint
- Emit:
  - `.ai/METRICS/daily-health/YYYY-MM-DD.md`
  - `.ai/METRICS/daily-health/runs.jsonl`
  - learning trace append to `.ai/EVOLVE_LOG.md`
  - optional `T-FIX-MQ-*` template when regressions appear

### Weekly `org-evolve`

- Run on a lower cadence because it explores repo-wide improvements, external patterns, and mutation candidates.
- Consume the last 7 daily health reports as operational evidence before selecting the next experiment.
- Keep mutation authority in weekly flow; daily flow only surfaces signals and task templates.

## Input to org-evolve Step 1.6

Add a new input before external search:

1. Read the previous day's daily health report.
2. Extract:
   - regressed cases
   - regressed metrics
   - learned success patterns
   - learned failure patterns
   - next improvement candidates
3. Use those items as search seeds for external scan.

Suggested prompt additions for Step 1.6:

- `Manager Quality regression fix patterns`
- `decision trace completeness eval ideas`
- `capability reuse automation patterns`
- `agent memory lint best practices`

This keeps external search anchored to observed regressions instead of generic exploration.

## Learning Contract

Daily health becomes the short-loop learner.

- If a metric improved, weekly evolve should avoid reopening the same area unless a new regression appears.
- If a metric regressed, weekly evolve should treat it as `P0 repair input`.
- If memory lint starts warning, weekly evolve should prioritize context integrity or traceability work.

## Scheduling Examples

### RemoteTrigger (Claude Code) example

```yaml
task: daily-health-check
schedule: "0 8 * * *"
command: "bash /workspace/scripts/evolve/daily-health-check.sh && bash /workspace/scripts/evolve/generate-fix-task.sh"
timezone: "Asia/Tokyo"
on_failure:
  - "append .ai/OWNER_COMMENTS.md via Manager"
  - "open follow-up T-FIX-MQ task if regression exists"
```

### cron example

```cron
0 8 * * * cd /Users/youyokotani/Dev/Private/OrgOS && bash scripts/evolve/daily-health-check.sh >> /tmp/orgos-daily-health.log 2>&1
5 8 * * * cd /Users/youyokotani/Dev/Private/OrgOS && bash scripts/evolve/generate-fix-task.sh >> /tmp/orgos-daily-health.log 2>&1
```

## Alert Path

Daily scheduling should not mutate shared ledgers directly. Alert routing should be:

1. daily script exits non-zero
2. scheduler captures stderr/stdout
3. Manager reads generated report or dry-run payload
4. Manager decides whether to:
   - activate generated `T-FIX-MQ-*`
   - record escalation in shared ledger
   - pause weekly evolve if regressions repeat

## Implementation Boundary

- `T-OS-183`: daily scripts, report format, fix-task template generation, integration memo
- `T-OS-183b`: wire org-evolve Step 1.6 to ingest previous-day learning automatically
