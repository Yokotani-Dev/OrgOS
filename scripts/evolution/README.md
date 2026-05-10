# Evolution Scripts

This directory contains the Phase 2 Self-Evolution detector and synthesis entry points.

## Detection Entry Point

- `detect.sh`: runs scanners, normalizes their JSON output, assigns `EVO-YYYY-MM-DD-NNN` IDs, deduplicates same-day events, appends `.ai/EVOLUTION/events.jsonl` with `--json`, and prints YAML with `--stdout`.

## Scanners

- `scanners/eval-scanner.sh`: reads `.ai/METRICS/manager-quality/*.jsonl` and `.ai/METRICS/daily-health/runs.jsonl`.
- `scanners/capability-scanner.sh`: reads `.ai/CAPABILITIES.yaml`; it does not call `scripts/capabilities/scan.sh` because that script writes the registry by design.
- `scanners/oip-scanner.sh`: reads `.ai/OIP/*.md` and flags open Draft/proposed OIPs older than 14 days.
- `scanners/memory-scanner.sh`: calls `scripts/memory/normalize-lint.sh --json` and scans `.claude/rules/*.md` headings read-only for duplication signals.
- `scanners/intel-scanner.sh`: reads `.ai/INTELLIGENCE/config.yaml` and raw collection state.

## Helpers

- `list-events.sh`: displays recent event rows in a compact table.
- `dedupe-events.sh`: rewrites `events.jsonl` with same-day duplicate `event_id` and duplicate fingerprint rows removed.

## Synthesis Entry Points

- `synthesize.sh`: reads `.ai/EVOLUTION/events.jsonl`, applies event filters, and writes `.ai/EVOLUTION/proposals/P-YYYY-MM-DD-NNN.yaml`.
- `peer-review.sh`: reads a proposal, fills `reviewer_b` and `agreement`, and escalates disagreement to OWNER_INBOX through `scripts/inbox/add-decision.sh`.
- `apply.sh`: reads a proposal and records a shadow or canary application in `.ai/EVOLUTION/applied/`.
- `circuit-breaker.sh`: guards automatic apply loops with per-cycle, per-day, and revert counters in `.ai/EVOLUTION/circuit-breaker.yaml`.
- `rollback.sh`: restores a canary target from its pre-apply snapshot and back-writes `rollback_ref` into the application record.

The proposal and application scripts use fixture inputs for the current Phase 2 tasks. They do not call an LLM API.

Example:

```bash
bash scripts/evolution/synthesize.sh --last 7d --problem-class P1
bash scripts/evolution/peer-review.sh P-2026-05-10-001
```

## Application Entry Points

`apply.sh` implements the first two rollout stages:

- `shadow`: validates the proposal and Iron Law target, writes an application record, and does not change the target file.
- `canary`: validates the proposal, applies one unified diff with `git apply`, writes an application record plus a 24h canary monitor marker, and stores a before snapshot for rollback.

`progressive` and `full` are accepted as stage names but intentionally blocked until later tasks implement production rollout behavior.

Stage defaults follow `autonomy_recommendation`:

| autonomy_recommendation | default stage |
|---|---|
| `silent_execute` | `shadow` |
| `execute_with_report` | `canary` |
| `ask_before_execute` | `canary` |
| `owner_only` | rejected by auto-apply |

Examples:

```bash
bash scripts/evolution/apply.sh P-2026-05-10-001 --stage shadow
bash scripts/evolution/apply.sh P-2026-05-10-001 --stage canary
bash scripts/evolution/rollback.sh AR-2026-05-10-001
```

Application records follow `.claude/schemas/application-record.yaml` and are written as:

```text
.ai/EVOLUTION/applied/AR-YYYY-MM-DD-NNN.yaml
```

Each application record includes `iteration_counter`, a snapshot of circuit-breaker counters after the successful apply. This records `current_cycle_apply_count`, `today_apply_count`, revert count, configured limits, and breaker state for audit.

Canary records also create:

```text
.ai/EVOLUTION/applied/AR-YYYY-MM-DD-NNN.before
.ai/EVOLUTION/applied/AR-YYYY-MM-DD-NNN.canary-monitor.yaml
```

Rollback creates:

```text
.ai/EVOLUTION/applied/RB-YYYY-MM-DD-NNN.yaml
.ai/EVOLUTION/applied/rollback-state.yaml
```

When `rollback-state.yaml` reaches `consecutive_reverts: 3`, `apply.sh` stops before proposal preflight. A Manager/Owner review must reset that state before future automatic application.

## Circuit Breaker

The Self-Evolution circuit breaker is single-host state stored at:

```text
.ai/EVOLUTION/circuit-breaker.yaml
```

Default limits are static:

```yaml
max_apply_per_cycle: 3
max_apply_per_day: 10
consecutive_revert_threshold: 3
scheduler_timeout_minutes: 30
```

Commands:

```bash
bash scripts/evolution/circuit-breaker.sh check
bash scripts/evolution/circuit-breaker.sh increment-apply
bash scripts/evolution/circuit-breaker.sh increment-revert
bash scripts/evolution/circuit-breaker.sh reset-cycle
bash scripts/evolution/circuit-breaker.sh reset-daily
bash scripts/evolution/circuit-breaker.sh trip "manual reason"
bash scripts/evolution/circuit-breaker.sh restore
```

`apply.sh` calls `check` before proposal preflight and calls `increment-apply` only after a shadow or canary apply succeeds. When the breaker is open, automatic apply exits gracefully with structured JSON logs and requires Owner review followed by `restore`.

`scripts/scheduler/run-detection.sh` wraps `detect`, `synthesize`, and `apply` with the configured timeout. The default is equivalent to `timeout 1800 bash scripts/evolution/detect.sh --json`; on systems without GNU `timeout`, the scheduler uses a Python timeout wrapper. If any sub-step times out, the scheduler trips the circuit breaker with the step name and timeout duration.

## Application Safety

The apply engine rejects protected targets before writing an application record. Protected targets include `AGENTS.md`, `CLAUDE.md`, `.claude/rules/rationalization-prevention.md`, `.claude/rules/request-intake-loop.md`, `.claude/rules/authority-layer.md`, files listed in `.claude/evals/KERNEL_FILES`, `.env`, `.env.*`, `secrets/**`, and existing `.claude` implementation/runtime areas outside the allowed schema addition path. Existing `.claude/rules/*.md` files containing an `Iron Law` section are also blocked from automatic apply.

Mutating rollout requires `proposed_change.diff` to contain an applicable unified diff. Proposals with `diff: null` can be recorded in `shadow`, but cannot enter `canary`.

All apply and rollback commands emit structured JSON logs with `trace: apply` or `trace: rollback`.

Useful smoke-test controls:

```bash
# Force a disagreement path without mutating OWNER_INBOX.
bash scripts/evolution/peer-review.sh P-2026-05-10-001 --fixture disagree --skip-inbox

# Exercise Iron Law rejection for a protected target.
bash scripts/evolution/synthesize.sh --event-id EVO-2026-05-08-077
```

`synthesize.sh` rejects proposals that target protected Iron Law files, including `.claude/rules/rationalization-prevention.md` and `.claude/rules/request-intake-loop.md`. Rejected proposals are still written with `status: rejected`, `estimated_risk_level: critical`, and `iron_law_check.status: rejected` so reviewers can inspect the trace.

When peer review disagrees and `--skip-inbox` is not set, `peer-review.sh` calls:

```bash
bash scripts/inbox/add-decision.sh --type type_a_direction ...
```

The returned `D-YYYY-MM-DD-NNN` id is stored in `escalation_target`.

## Contract

Scanner scripts must support:

```bash
bash scripts/evolution/scanners/<name>-scanner.sh --json
```

They should return a JSON array of event candidates. Candidates may omit `event_id`; `detect.sh` owns ID assignment and append semantics.

Proposal files follow `.claude/schemas/evolution-proposal.yaml`. The required review fields are:

- `reviewer_a`: fixture synthesizer A for this task.
- `reviewer_b`: independent fixture reviewer B after `peer-review.sh` runs.
- `agreement`: `agree` or `disagree` after peer review.
- `escalation_target`: null unless disagreement created an OWNER_INBOX Decision Card.
