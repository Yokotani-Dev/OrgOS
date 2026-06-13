# Intelligence Pipeline

This directory contains the MVP weekly Intelligence pipeline for OrgOS:

1. `collect.sh` fetches configured external feeds into `.ai/_machine/intelligence/raw/<source_id>/<YYYY-MM-DD>.xml`.
2. `summarize.sh` reads the latest seven-day raw window and writes `.ai/_machine/intelligence/weekly/<YYYY-WW>.md`.
3. `emit-oip.sh` converts the newest weekly summary into an OIP candidate in `.ai/_machine/intelligence/reports/`.

The pipeline is proposal-only. It does not call an LLM, does not apply OIPs, and does not write Owner or Manager ledgers.

## Configuration

Sources live in `.ai/_machine/intelligence/config.yaml`.

Each source must define:

- `id`: stable directory-safe source ID.
- `type`: `rss`, `atom`, or `json`.
- `url`: external source URL.
- `fetch_cadence`: currently `weekly`.
- `cache_ttl`: defaults to `24h`.

Do not hardcode industry sources in the scripts. Add or remove sources in config.

## Usage

Run the weekly pipeline from the repository root:

```bash
scripts/intel/collect.sh
scripts/intel/summarize.sh
scripts/intel/emit-oip.sh
```

Useful smoke-test overrides:

```bash
INTEL_MAX_TIME=1 scripts/intel/collect.sh
INTEL_RAW_DIR=/tmp/intel-raw INTEL_WEEKLY_DIR=/tmp/intel-weekly scripts/intel/summarize.sh
INTEL_WEEKLY_DIR=/tmp/intel-weekly INTEL_REPORTS_DIR=/tmp/intel-reports scripts/intel/emit-oip.sh
```

## Failure Behavior

Network and HTTP failures are log-only. `collect.sh` emits a structured warning and skips the failed source, then exits successfully so offline weekly runs do not block the rest of the pipeline.

All scripts emit JSON logs to stderr with:

- `ts`
- `level`
- `event`
- `message`
- optional context fields

## Outputs

Raw fetches:

```text
.ai/_machine/intelligence/raw/<source_id>/<YYYY-MM-DD>.xml
.ai/_machine/intelligence/raw/<source_id>/<YYYY-MM-DD>.json
```

Weekly summaries:

```text
.ai/_machine/intelligence/weekly/<YYYY-WW>.md
```

OIP candidates:

```text
.ai/_machine/intelligence/reports/OIP-INTEL-<YYYY-WW>.md
```

## OIP Handoff

Generated OIP candidates include:

- `id`
- `title`
- `source_refs`
- `suggested_action`
- `handoff_target: T-OS-324`

They are intentionally candidates only. Owner or Manager approval is required before any follow-up task applies changes.
