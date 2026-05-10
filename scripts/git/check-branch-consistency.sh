#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/git/check-branch-consistency.sh [--report] [--block-if-mismatch] [--require-lock]
  scripts/git/check-branch-consistency.sh --update-expected <branch>

Checks the current git branch against .claude/state/expected_branch_<sessionId>.
--report returns JSON for CI/monitoring.
--block-if-mismatch prints a clear blocking error when current != expected.
--require-lock requires the current session to hold .claude/state/git.lock.
--update-expected records an Owner-approved expected branch update.
USAGE
}

json_escape() {
  python3 -c 'import json, sys; print(json.dumps(sys.stdin.read())[1:-1])'
}

utc_now() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
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
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

current_branch() {
  git branch --show-current
}

require_git_lock() {
  local lock_file="$1"
  local session_id="$2"

  python3 - "$lock_file" "$session_id" <<'PY'
import fcntl
import json
import sys

lock_file, expected_session = sys.argv[1:]

try:
    handle = open(lock_file, "a+", encoding="utf-8")
except OSError as exc:
    print(f"error=git_lock_open_failed lock_file={lock_file} detail={exc}", file=sys.stderr)
    sys.exit(1)

try:
    fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    pass
else:
    fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
    print(
        f"error=git_lock_required lock_file={lock_file} "
        "reason=lock_is_not_held recovery=run_scripts_git_acquire_lock",
        file=sys.stderr,
    )
    sys.exit(1)

try:
    handle.seek(0)
    payload = json.load(handle)
except (json.JSONDecodeError, OSError) as exc:
    print(
        f"error=git_lock_holder_unreadable lock_file={lock_file} detail={exc} "
        "recovery=manual_lock_holder_review",
        file=sys.stderr,
    )
    sys.exit(1)

holder_session = str(payload.get("sessionId", payload.get("session_id", "")))
holder_pid = payload.get("pid", "unknown")
if holder_session != expected_session:
    print(
        f"error=git_lock_held_by_other_session lock_file={lock_file} "
        f"expected_sessionId={expected_session} holder_sessionId={holder_session or 'unknown'} "
        f"holder_pid={holder_pid} recovery=wait_or_release_lock",
        file=sys.stderr,
    )
    sys.exit(1)

print(
    f"event=git_lock_required_passed lock_file={lock_file} "
    f"holder_sessionId={holder_session} holder_pid={holder_pid}",
    file=sys.stderr,
)
PY
}

read_expected_branch() {
  local state_file="$1"
  if [[ ! -f "$state_file" ]]; then
    return 1
  fi
  python3 - "$state_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)
print(payload.get("expected_branch", ""))
PY
}

write_expected_branch() {
  local state_file="$1"
  local session_id="$2"
  local branch="$3"
  local root="$4"
  mkdir -p "$(dirname "$state_file")"
  python3 - "$state_file" "$session_id" "$branch" "$root" "$(utc_now)" <<'PY'
import json
import sys

state_file, session_id, branch, root, timestamp = sys.argv[1:]
payload = {
    "session_id": session_id,
    "recorded_at": timestamp,
    "expected_branch": branch,
    "worktree_path": root,
}
with open(state_file, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
}

mode="text"
update_branch=""
block_if_mismatch="false"
require_lock="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --report)
      mode="report"
      shift
      ;;
    --block-if-mismatch)
      block_if_mismatch="true"
      shift
      ;;
    --require-lock)
      require_lock="true"
      shift
      ;;
    --update-expected)
      if [[ $# -ne 2 ]]; then
        usage >&2
        exit 2
      fi
      mode="update"
      update_branch="$2"
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

root="$(repo_root)"
session_raw="${CLAUDE_SESSION_ID:-${CODEX_SESSION_ID:-${ORGOS_SESSION_ID:-default}}}"
session_id="$(safe_session_id "$session_raw")"
state_dir="$root/.claude/state"
state_file="$state_dir/expected_branch_${session_id}"
lock_file="$state_dir/git.lock"
current="$(current_branch)"

if [[ "$mode" == "update" ]]; then
  if [[ "$block_if_mismatch" == "true" || "$require_lock" == "true" ]]; then
    usage >&2
    exit 2
  fi
  write_expected_branch "$state_file" "$session_id" "$update_branch" "$root"
  printf 'updated expected branch for session %s: %s\n' "$session_id" "$update_branch"
  exit 0
fi

if [[ "$require_lock" == "true" ]]; then
  require_git_lock "$lock_file" "$session_id"
fi

if ! expected="$(read_expected_branch "$state_file" 2>/dev/null)"; then
  write_expected_branch "$state_file" "$session_id" "$current" "$root"
  expected="$current"
  initialized="true"
else
  initialized="false"
fi

if [[ "$current" == "$expected" ]]; then
  status="ok"
  exit_code=0
else
  status="mismatch"
  exit_code=1
fi

if [[ "$mode" == "report" ]]; then
  printf '{'
  printf '"status":"%s",' "$(printf '%s' "$status" | json_escape)"
  printf '"session_id":"%s",' "$(printf '%s' "$session_id" | json_escape)"
  printf '"expected_branch":"%s",' "$(printf '%s' "$expected" | json_escape)"
  printf '"current_branch":"%s",' "$(printf '%s' "$current" | json_escape)"
  printf '"state_file":"%s",' "$(printf '%s' "$state_file" | json_escape)"
  printf '"initialized":%s,' "$initialized"
  printf '"checked_at":"%s"' "$(utc_now)"
  printf '}\n'
else
  printf 'status=%s\n' "$status"
  printf 'session_id=%s\n' "$session_id"
  printf 'expected_branch=%s\n' "${expected:-"(detached/empty)"}"
  printf 'current_branch=%s\n' "${current:-"(detached/empty)"}"
  printf 'state_file=%s\n' "$state_file"
  printf 'initialized=%s\n' "$initialized"
fi

if [[ "$status" == "mismatch" && "$block_if_mismatch" == "true" ]]; then
  {
    printf 'OrgOS blocked: git branch mismatch detected.\n'
    printf 'Expected branch: %s\n' "${expected:-"(detached/empty)"}"
    printf 'Current branch: %s\n' "${current:-"(detached/empty)"}"
    printf 'Session: %s\n' "$session_id"
    printf 'State file: %s\n' "$state_file"
    printf 'Recovery: stop and ask Owner; if intentional, run --update-expected before retrying.\n'
  } >&2
fi

exit "$exit_code"
