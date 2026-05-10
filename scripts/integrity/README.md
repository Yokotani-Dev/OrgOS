# Integrity Scans

`scan-stale.sh` creates a point-in-time consistency report for stale OrgOS records.

## Usage

```bash
bash scripts/integrity/scan-stale.sh
```

The script writes:

```text
.ai/INTEGRITY/scan-<timestamp>.md
```

It also emits structured JSON logs to stderr with `event`, `error_class`, and `recovery` fields for failures.

## Checks

- OIP records older than 90 days.
- Capabilities with `verified_at` / `last_verified_at` older than 30 days, or never verified.
- Pending `DECISIONS.md` entries older than 14 days.
- Queued `TASKS.yaml` entries without recent activity older than 30 days.

## Fixture Clock

Use a fixed clock for deterministic smoke tests:

```bash
bash scripts/integrity/scan-stale.sh --now 2026-05-10T00:00:00Z
```

## Scope

The script is read-only for OrgOS ledgers and only writes the generated report. It does not update OIP, capability, decision, or task state.
