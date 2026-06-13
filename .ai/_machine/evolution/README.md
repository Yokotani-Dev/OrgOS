# Evolution Event Store

`.ai/EVOLUTION/events.jsonl` is the Phase 2 Self-Evolution Engine input queue. Each row is a normalized event that follows `.claude/schemas/evolution-event.yaml`.

## Event Format

Required fields:

- `event_id`: `EVO-YYYY-MM-DD-NNN`, assigned by `scripts/evolution/detect.sh`
- `detected_at`: ISO8601 timestamp
- `source`: scanner source enum
- `event_type`: normalized signal type
- `severity`: `P0` to `P3`
- `confidence`: `0.0` to `1.0`
- `novelty`: `first_seen`, `recurring`, or `transient`
- `target_artifacts`: affected paths and line numbers
- `evidence`: short snippets proving the signal
- `proposed_action`, `estimated_impact`, `estimated_risk`
- `autonomy_candidate`, `blast_radius`, `recommended_next`

## Scanners

- `eval`: reads Manager Quality and daily-health metrics; emits `eval_regression` and `ux_drift`.
- `capability`: reads `.ai/CAPABILITIES.yaml`; emits `capability_degraded`.
- `oip`: reads `.ai/OIP/*.md`; emits `oip_stale`.
- `memory`: runs `scripts/memory/normalize-lint.sh --json` and scans rule headings read-only; emits `rule_stale`.
- `intel`: reads `.ai/INTELLIGENCE/`; emits `intel_stale`.

## Commands

```bash
bash scripts/evolution/detect.sh --json
bash scripts/evolution/detect.sh --json --stdout
bash scripts/evolution/detect.sh --scanner oip --stdout
bash scripts/evolution/list-events.sh 20
bash scripts/evolution/dedupe-events.sh
```

`detect.sh` deduplicates same-day events before append. Re-running the same scanner on the same day should not append duplicate rows.

## Extension

Add a scanner under `scripts/evolution/scanners/<name>-scanner.sh` that supports `--json` and prints a compact JSON array. The detector assigns `event_id`, validates enum values, deduplicates same-day events, appends JSONL only when `--json` is passed, and prints YAML only when `--stdout` is passed.
