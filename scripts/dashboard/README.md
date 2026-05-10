# Result-First Dashboard

`scripts/dashboard/render.sh` regenerates `.ai/DASHBOARD.md` with the Phase 2 result-first sections at the top.

## Usage

```bash
bash scripts/dashboard/render.sh
```

The script reads only repository-local dashboard inputs:

- `.ai/OWNER_INBOX.md` for pending Decision Cards and weekly Owner decisions
- `.ai/EVOLUTION/applied/*.yaml` for recent and monthly application records
- `.ai/TASKS.yaml` for current blocked tasks
- `.ai/EVOLUTION/events.jsonl` for recent problem classes, priorities, and capability signals

## Render Contract

The generated block is bounded by:

```markdown
<!-- ORGOS:RESULT-FIRST-DASHBOARD:BEGIN -->
<!-- ORGOS:RESULT-FIRST-DASHBOARD:END -->
```

On the first render, existing sections beginning at the first `##` heading are preserved below the generated block. On later renders, only the generated block is replaced and the preserved body below it is left intact.

Missing or empty data is rendered as `(なし)`. Parse errors are skipped with structured JSON logs on stderr.

## Observability

The renderer emits JSONL-style structured logs to stderr, including:

- `dashboard_render_start`
- `decision_cards_loaded`
- `application_records_loaded`
- `events_loaded`
- `dashboard_metrics`
- `dashboard_render_complete`
- `dashboard_render_end`

## Security Boundary

The renderer does not access network resources and does not read `.env`, `.env.*`, or `secrets/**`. Inputs are fixed repo-local ledger paths needed to render the dashboard.
