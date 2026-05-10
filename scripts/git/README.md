# Git Coordination Utilities

OrgOS uses a single-host git coordination lock to avoid concurrent destructive
git operations in the same worktree.

## Lock Acquire

```bash
bash scripts/git/acquire-lock.sh [--timeout 30]
```

The script opens `.claude/state/git.lock`, acquires an exclusive `flock` via
Python `fcntl.flock`, writes structured holder metadata, and keeps running until
released.

Holder metadata:

```json
{
  "pid": 12345,
  "sessionId": "default",
  "acquired_at": "2026-05-10T00:00:00Z",
  "lock_file": "/path/to/.claude/state/git.lock",
  "worktree_path": "/path/to/repo"
}
```

If the lock cannot be acquired before the timeout, the script exits `1` and
prints the recorded holder pid, session id, and acquisition time.

## Lock Release

```bash
bash scripts/git/release-lock.sh
```

The release script reads the holder pid from `.claude/state/git.lock`, sends
`SIGTERM`, and waits for the kernel lock to become available. If the holder is
gone but metadata remains, it reports a manual stale-lock review instead of
removing the file automatically.

## Scope

- Single host only.
- No distributed lock service.
- No automatic stale-lock recovery.
- `status`, `log`, and `diff` do not need the lock.
- Destructive git operations should acquire the lock before T-OS-361 branch
  consistency checks: `commit`, `checkout`, `switch`, `merge`, `rebase`,
  `stash`, and `push`.

## Current Integration Note

T-OS-363 requires `.claude/hooks/pretool_policy.py` integration, but this Codex
Worker is constrained by AGENTS.md, which marks `.claude/**` as an absolute
no-edit path. The intended additive integration is:

1. Detect destructive git operations before `verify_branch_consistency`.
2. Acquire `.claude/state/git.lock` with a 30 second timeout.
3. Continue into the existing T-OS-361 branch consistency checks.
4. Keep read-only git commands lock-free.
