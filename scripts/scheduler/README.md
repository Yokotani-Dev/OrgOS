# OrgOS Scheduler

This directory contains the Always-On shadow scheduler entry points for
T-OS-329. It wires the existing evolution pipeline:

```bash
bash scripts/evolution/detect.sh --json
bash scripts/evolution/synthesize.sh --last 7d
bash scripts/evolution/apply.sh <proposal> --stage shadow
```

## Run Modes

- `manual`: `bash scripts/scheduler/run-detection.sh`
- `dry-run`: `bash scripts/scheduler/run-detection.sh --dry-run`
- `launchd`: use `com.orgos.scheduler.plist.template`
- `cron`: use `setup-cron.sh` to print the manual crontab entry
- `GitHub Actions`: `.github/workflows/orgos-scheduler.yml`

Default execution is `shadow`; it records application state but does not modify
target files. `canary` and `progressive` are accepted by the wrapper for staged
operation, but this Work Order keeps scheduled operation in `shadow`.

## Logs And Recovery

Each run writes a structured log to:

```text
.ai/SCHEDULER/runs/<timestamp>.log
```

Failure classes:

- `network`: transient connectivity or HTTP failures; retried once by default.
- `lock`: concurrent run protection; stale locks are removed automatically.
- `iron_law`: protected target or Owner-only approval; automatic apply stops.
- `unknown`: inspect the run log and rerun with `--dry-run`.

No scheduler template stores secrets. GitHub Actions secrets, launchd
installation, and crontab registration remain manual Owner operations.
