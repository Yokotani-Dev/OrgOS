# T-OS-321b Result

## Status
DONE_WITH_CONCERNS

Reason: implementation and functional verification are complete, but `shellcheck` is not installed in this sandbox, so shellcheck itself could not be executed. Bash syntax checks and Python compile checks passed.

## Changed Files
- `scripts/inbox/add-decision.sh`
- `scripts/inbox/list-pending.sh`
- `scripts/inbox/expire-old.sh`
- `scripts/inbox/archive.sh`
- `scripts/inbox/inbox.py`
- `.ai/CODEX/RESULTS/T-OS-321b.md`

## Verification
- `bash scripts/inbox/add-decision.sh --help`: passed
- `bash scripts/inbox/list-pending.sh --help`: passed
- `bash scripts/inbox/expire-old.sh --help`: passed
- `bash scripts/inbox/archive.sh --help`: passed
- `bash scripts/inbox/list-pending.sh`: passed, displayed `0 pending decisions`
- `bash scripts/inbox/list-pending.sh --json`: passed, displayed `[]`
- `PYTHONPYCACHEPREFIX=/tmp/orgos-pycache python3 -m py_compile scripts/inbox/inbox.py`: passed
- `bash -n scripts/inbox/add-decision.sh scripts/inbox/list-pending.sh scripts/inbox/expire-old.sh scripts/inbox/archive.sh`: passed
- `shellcheck`: not run, command unavailable in sandbox
- Isolated temp repo smoke test:
  - `add-decision.sh` created `D-2026-05-08-001`
  - `expire-old.sh` handled `auto_apply` and `no_op`
  - `archive.sh` moved resolved cards to `## Archived`
  - `defer_7d` extended deadline by 7 days
  - `escalate` moved an overdue pending card to the high priority section

## Handoff Packet

### Summary
- Added four OWNER_INBOX helper entrypoints under `scripts/inbox/`.
- Shared implementation lives in `scripts/inbox/inbox.py`.
- The scripts parse `decision-card` fenced YAML blocks, validate against `.claude/schemas/decision-card.yaml`, and update `.ai/OWNER_INBOX.md` atomically when mutation is requested.

### Usage
```bash
bash scripts/inbox/add-decision.sh \
  --type type_a \
  --decision "Decision text" \
  --recommendation A \
  --risk low \
  --options '[{"key":"A","label":"APPROVE","consequence":"Proceed.","is_recommended":true},{"key":"B","label":"DEFER","consequence":"Wait.","is_recommended":false},{"key":"C","label":"REJECT","consequence":"Stop.","is_recommended":false}]' \
  --deadline 2026-05-15T12:00:00+09:00 \
  --default-if-no-response no_op
```

```bash
bash scripts/inbox/list-pending.sh
bash scripts/inbox/list-pending.sh --json
bash scripts/inbox/expire-old.sh
bash scripts/inbox/archive.sh
```

### Notes
- `--type type_a/b/c/d` is mapped to the schema enum values.
- `--recommendation A/B/C` selects the recommended option key; the schema `recommendation` value is derived from the selected option label when it is `APPROVE`, `DEFER`, or `REJECT`.
- `--default-if-no-response` is optional and defaults to `no_op` because the work order did not define this add-time argument, while the schema requires the field.
- `expire-old.sh` logs actions to stdout and supports optional append logging with `--log <path>`.
- No direct mutation command was run against the real `.ai/OWNER_INBOX.md`; only `list-pending.sh` was run on the real file.
