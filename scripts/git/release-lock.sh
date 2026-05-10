#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/git/release-lock.sh

Releases the OrgOS git coordination lock by terminating the holder process
recorded in .claude/state/git.lock.
USAGE
}

repo_root() {
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    printf '%s\n' "$CLAUDE_PROJECT_DIR"
    return
  fi
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

is_lock_free() {
  local lock_file="$1"
  python3 - "$lock_file" <<'PY'
import fcntl
import sys

path = sys.argv[1]
try:
    handle = open(path, "a+", encoding="utf-8")
    fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
except BlockingIOError:
    sys.exit(1)
PY
}

holder_pid() {
  local lock_file="$1"
  python3 - "$lock_file" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        payload = json.load(handle)
except (FileNotFoundError, json.JSONDecodeError, OSError):
    sys.exit(1)

pid = payload.get("pid")
if not isinstance(pid, int) or pid <= 0:
    sys.exit(1)

print(pid)
PY
}

holder_field() {
  local lock_file="$1"
  local field="$2"
  python3 - "$lock_file" "$field" <<'PY'
import json
import sys

path, field = sys.argv[1:]
try:
    with open(path, encoding="utf-8") as handle:
        payload = json.load(handle)
except (FileNotFoundError, json.JSONDecodeError, OSError):
    print("unknown")
    sys.exit(0)

print(payload.get(field, "unknown"))
PY
}

if [[ $# -gt 0 ]]; then
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
fi

root="$(repo_root)"
lock_file="$root/.claude/state/git.lock"

if [[ ! -f "$lock_file" ]]; then
  printf 'event=git_lock_not_found lock_file=%s\n' "$lock_file"
  exit 0
fi

if is_lock_free "$lock_file"; then
  printf 'event=git_lock_already_free lock_file=%s\n' "$lock_file"
  exit 0
fi

if ! pid="$(holder_pid "$lock_file")"; then
  printf 'error=git_lock_holder_unknown lock_file=%s recovery=manual_stale_lock_review\n' "$lock_file" >&2
  exit 1
fi

session_id="$(holder_field "$lock_file" "sessionId")"
acquired_at="$(holder_field "$lock_file" "acquired_at")"

if ! kill -0 "$pid" 2>/dev/null; then
  printf 'error=git_lock_holder_not_running holder_pid=%s lock_file=%s recovery=manual_stale_lock_review\n' "$pid" "$lock_file" >&2
  exit 1
fi

kill -TERM "$pid"

deadline=$((SECONDS + 5))
while [[ "$SECONDS" -le "$deadline" ]]; do
  if is_lock_free "$lock_file"; then
    printf 'event=git_lock_released holder_pid=%s holder_sessionId=%s holder_acquired_at=%s lock_file=%s\n' "$pid" "$session_id" "$acquired_at" "$lock_file"
    exit 0
  fi
  sleep 0.1
done

printf 'error=git_lock_release_timeout holder_pid=%s holder_sessionId=%s lock_file=%s recovery=manual_process_review\n' "$pid" "$session_id" "$lock_file" >&2
exit 1
