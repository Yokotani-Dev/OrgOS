# Codex worktree runner

Codex workers must run in an isolated git worktree so that hidden checkout
operations cannot switch the Manager session's current branch.

## Enforcement scripts

T-OS-372 adds standalone validation scripts for the Codex wrapper layer. They
are intentionally separate from `run-in-worktree.sh`; wrapper integration is
handled by T-OS-373.

Pre-exec validation:

```bash
bash scripts/codex/pre-exec-validate.sh T-XXX
```

This reads `.ai/TASKS.yaml` and `.claude/evals/KERNEL_FILES`, then blocks Codex
delegation when:

- `autonomy_level` is `owner_only`
- `allowed_paths` is empty, invalid, or over-broad such as `**`
- `allowed_paths` overlaps a protected `KERNEL_FILES` entry

Autonomy matrix validation:

```bash
bash scripts/authority/check-autonomy-runtime.sh T-XXX
```

This applies the Authority Layer risk/reversibility matrix and blocks
contradictions such as `risk_level=critical` without `owner_only`, or
`risk_level=high` plus `reversibility=irreversible` without `owner_only`.

Post-exec audit:

```bash
bash scripts/codex/post-exec-audit.sh T-XXX .worktrees/T-XXX
```

This inspects `git diff --name-only HEAD` plus untracked files in the worker
worktree. Files outside task `allowed_paths` are reverted. Files matching
`KERNEL_FILES` are always reverted and logged as critical violations. The audit
record is written to:

```text
.ai/_machine/codex/AUDIT/<TASK_ID>.yaml
```

The scripts emit structured `key=value` logs to stderr for validation and audit
traceability.

## Command migration

Old command:

```bash
/opt/homebrew/bin/codex exec --full-auto - < .ai/_machine/codex/ORDERS/T-XXX.md
```

New command:

```bash
bash scripts/codex/run-in-worktree.sh T-XXX
```

Manager-side command replacement is intentionally out of scope for this task
and should be handled by T-OS-362b.

## Runner behavior

`run-in-worktree.sh` performs the following steps:

1. Creates `.worktrees/<TASK_ID>` from the current `HEAD`.
2. Runs Codex inside that worktree:

   ```bash
   /opt/homebrew/bin/codex exec --full-auto --skip-git-repo-check \
     --output-last-message ../../.ai/_machine/codex/RESULTS/<TASK_ID>.txt \
     - < ../../.ai/_machine/codex/ORDERS/<TASK_ID>.md
   ```

3. Removes the worktree after Codex exits.

Use `--keep-worktree` when you need to inspect a failed run:

```bash
bash scripts/codex/run-in-worktree.sh T-XXX --keep-worktree
```

The script logs structured `key=value` events for worktree creation, Codex
execution, and cleanup status.

## Why worktrees

Multiple Codex CLI sessions in the same working directory can trigger hidden
checkout behavior. Running each worker in `.worktrees/<TASK_ID>` isolates the
worker's git state from the Manager checkout while preserving normal repository
semantics.

`.claude/settings.json` already allows `.worktrees` as an additional directory,
so this wrapper uses the existing project-level design instead of adding a new
workspace convention.

## Cleanup

Remove stale `T-OS-*` worktrees older than 24 hours:

```bash
bash scripts/codex/cleanup-worktrees.sh
```

Preview targets without deleting:

```bash
bash scripts/codex/cleanup-worktrees.sh --dry-run
```

Remove every worktree under `.worktrees/` with a confirmation prompt:

```bash
bash scripts/codex/cleanup-worktrees.sh --all
```

Preview the `--all` target set:

```bash
bash scripts/codex/cleanup-worktrees.sh --all --dry-run
```
