# Eval Harness Fixtures

This directory contains concrete fixture harnesses for Manager Quality Eval migration.

## Commands

Run one synthetic Owner judgment fixture:

```bash
scripts/eval/synthetic-owner.sh .claude/evals/synthetic-owner/01-approve-complete-handoff.yaml
```

Run all synthetic Owner fixtures:

```bash
for f in .claude/evals/synthetic-owner/*.yaml; do
  scripts/eval/synthetic-owner.sh "$f"
done
```

Run one Manager response fixture:

```bash
scripts/eval/fixture-response.sh .claude/evals/fixtures/01-repeated-question.yaml
```

Run all Manager response fixtures:

```bash
for f in .claude/evals/fixtures/*.yaml; do
  scripts/eval/fixture-response.sh "$f"
done
```

Each command emits one JSON object with:

- `status`
- `fixture_id`
- `measured`
- `fallback_used`
- `reason`
- `reasoning_trace`

`measured=true` and `fallback_used=false` are required for a passing concrete eval.
Missing fields, invalid YAML, invalid regexes, secret-looking fixture content, and
default fallback behavior fail closed.

## Fixture Schemas

Synthetic Owner fixtures live in `.claude/evals/synthetic-owner/`.

Required fields:

```yaml
scenario: "..."
expected_verdict: approve # approve | reject | needs_more_context
reasoning: "..."
signals:
  acceptance_met: true
  blocker_present: false
  insufficient_context: false
  high_risk_unmitigated: false
```

Manager response fixtures live in `.claude/evals/fixtures/`.

Required fields:

```yaml
request: "..."
expected_response_pattern: "regular expression"
actual_response_to_evaluate: "..."
forbidden_patterns: []
```

Fixtures must be redacted. Do not place real credentials, API keys, tokens, or
password values in these files.

## Manager Quality Eval Migration Path

The current Manager Quality Eval entry point is `.claude/evals/manager-quality/run.sh`,
with `scripts/eval/manager-quality-runner.sh` delegating to it. The existing
decision trace judge still has a legacy metadata fallback when no machine-readable
handoff packet is found.

To remove legacy fallback passes in the runner, wire these checks before accepting
`decision_trace_completeness`:

1. Run every `.claude/evals/synthetic-owner/*.yaml` through `scripts/eval/synthetic-owner.sh`.
2. Run every `.claude/evals/fixtures/*.yaml` through `scripts/eval/fixture-response.sh`.
3. Require every JSON result to have `status="passed"`, `measured=true`, and `fallback_used=false`.
4. If any fixture fails or reports `measured=false`, fail the Manager Quality Eval instead of using USER_PROFILE metadata fallback.
5. Keep real LLM calls out of this path until the next CI integration task.

This preserves the existing `Handoff Packet` rubric from `.claude/schemas/handoff-packet.yaml`
while forcing the eval to inspect concrete Owner judgment fixtures and Manager response traces.
