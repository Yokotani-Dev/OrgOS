# Journey Ledger Scripts

`scripts/journeys` manages `.ai/JOURNEYS.yaml`, the runtime ledger for the User Journey Sync Iron Law.

## Files

- `.ai/JOURNEYS.yaml`: project journey ledger.
- `.ai/JOURNEYS.example.yaml`: commit-safe template and example.
- `.claude/schemas/journey.yaml`: schema used by the validator.
- `scripts/journeys/validate.sh`: schema and cross-reference validator.
- `scripts/journeys/init.sh`: draft journey skeleton generator.

## Initialize A Draft

```bash
bash scripts/journeys/init.sh J-EXAMPLE-001
```

The command appends a schema-shaped draft journey with:

- `sync_status: draft`
- `confirmed_at:` and `confirmed_by:` left null
- placeholder `current_flow`, `target_flow`, `happy_path`, and `error_paths`

The command refuses duplicate IDs and validates the ledger after writing.

## Validate

```bash
bash scripts/journeys/validate.sh
```

Validation checks:

- top-level `journeys` structure and journey schema fields
- `sync_status` enum: `draft`, `confirmed`, `superseded`
- `confirmed_at` and `confirmed_by` when `sync_status: confirmed`
- `related_milestone` exists in `.ai/GOALS.yaml` when present
- `related_tasks` exist in `.ai/TASKS.yaml` when present
- `happy_path` and `error_paths` shape and required fields

The validator exits `0` when the ledger is valid and `1` when validation fails. Logs are JSON objects on stderr so callers can parse failures without scraping human text.

## Operating Rule

Confirmed journeys are Owner-agreed records. If a target flow changes after confirmation, create a new draft journey or mark the old journey as `superseded`; do not silently edit confirmed business flow.
