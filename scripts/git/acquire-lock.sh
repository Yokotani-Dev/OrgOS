#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/git/acquire-lock.sh [--timeout 30]

Acquires the single-host OrgOS git coordination lock and holds it until
released by scripts/git/release-lock.sh or process termination.
USAGE
}

safe_session_id() {
  local raw="$1"
  local cleaned
  cleaned="$(printf '%s' "$raw" | tr -c 'A-Za-z0-9_.-' '_')"
  cleaned="${cleaned:0:120}"
  if [[ -z "$cleaned" ]]; then
    printf 'default'
  else
    printf '%s' "$cleaned"
  fi
}

repo_root() {
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    printf '%s\n' "$CLAUDE_PROJECT_DIR"
    return
  fi
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

timeout="30"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout)
      if [[ $# -lt 2 ]]; then
        usage >&2
        exit 2
      fi
      timeout="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

if ! [[ "$timeout" =~ ^[0-9]+$ ]]; then
  printf 'error=invalid_timeout timeout=%s\n' "$timeout" >&2
  exit 2
fi

root="$(repo_root)"
state_dir="$root/.claude/state"
lock_file="$state_dir/git.lock"
session_raw="${CLAUDE_SESSION_ID:-${CODEX_SESSION_ID:-${ORGOS_SESSION_ID:-default}}}"
session_id="$(safe_session_id "$session_raw")"

mkdir -p "$state_dir"

python3 - "$lock_file" "$timeout" "$session_id" "$root" <<'PY'
import fcntl
import json
import os
import signal
import sys
import time
from datetime import datetime, timezone


def utc_now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def read_holder(path):
    try:
        with open(path, encoding="utf-8") as handle:
            payload = json.load(handle)
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return {}
    return payload if isinstance(payload, dict) else {}


def holder_summary(path):
    holder = read_holder(path)
    pid = holder.get("pid", "unknown")
    session_id = holder.get("sessionId", holder.get("session_id", "unknown"))
    acquired_at = holder.get("acquired_at", "unknown")
    return f"holder_pid={pid} holder_sessionId={session_id} holder_acquired_at={acquired_at}"


lock_file, timeout_raw, session_id, root = sys.argv[1:]
timeout = int(timeout_raw)
deadline = time.monotonic() + timeout
handle = open(lock_file, "a+", encoding="utf-8")

while True:
    try:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        break
    except BlockingIOError:
        if time.monotonic() >= deadline:
            print(
                "error=git_lock_timeout "
                f"timeout_seconds={timeout} lock_file={lock_file} {holder_summary(lock_file)}",
                file=sys.stderr,
            )
            sys.exit(1)
        time.sleep(min(0.1, max(0.01, deadline - time.monotonic())))

payload = {
    "pid": os.getpid(),
    "sessionId": session_id,
    "acquired_at": utc_now(),
    "lock_file": lock_file,
    "worktree_path": os.path.abspath(root),
}
handle.seek(0)
handle.truncate()
json.dump(payload, handle, ensure_ascii=True, sort_keys=True)
handle.write("\n")
handle.flush()
os.fsync(handle.fileno())
print(
    "event=git_lock_acquired "
    f"pid={payload['pid']} sessionId={session_id} acquired_at={payload['acquired_at']} lock_file={lock_file}",
    flush=True,
)

running = True


def request_release(signum, frame):
    del signum, frame
    global running
    running = False


signal.signal(signal.SIGTERM, request_release)
signal.signal(signal.SIGINT, request_release)

while running:
    time.sleep(0.2)

released = {
    "released_at": utc_now(),
    "released_pid": os.getpid(),
    "sessionId": session_id,
    "lock_file": lock_file,
    "worktree_path": os.path.abspath(root),
}
handle.seek(0)
handle.truncate()
json.dump(released, handle, ensure_ascii=True, sort_keys=True)
handle.write("\n")
handle.flush()
os.fsync(handle.fileno())
fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
print(
    "event=git_lock_released "
    f"pid={released['released_pid']} sessionId={session_id} released_at={released['released_at']} lock_file={lock_file}",
    flush=True,
)
PY
