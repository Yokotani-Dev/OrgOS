# OrgOS Scheduler State

This directory stores scheduler runtime logs and dry-run state.

- `runs/`: structured logs from `scripts/scheduler/run-detection.sh`
- `dry-run/`: isolated event/proposal/apply state created by `--dry-run`

The production scheduler uses `.ai/EVOLUTION` for events, proposals, and shadow
application records. Dry runs are intentionally isolated here so validation does
not mutate evolution state.
