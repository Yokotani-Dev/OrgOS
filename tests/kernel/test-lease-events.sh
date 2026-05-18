#!/usr/bin/env bash
# Lease script event emission tests
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
ACQUIRE=${ACQUIRE:-"$REPO_ROOT/scripts/org/acquire-lease.sh"}
RELEASE=${RELEASE:-"$REPO_ROOT/scripts/org/release-lease.sh"}

pass_count=0
fail_count=0
current_test_failed=0

fail() {
  printf 'not ok - %s\n' "$1" >&2
  current_test_failed=1
  return 1
}

assert_exists() {
  local path="$1"
  local msg="$2"
  [ -e "$path" ] || fail "$msg: missing $path"
}

assert_not_exists() {
  local path="$1"
  local msg="$2"
  [ ! -e "$path" ] || fail "$msg: unexpected $path"
}

setup_repo_fixture() {
  local tmp_dir repo
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-lease-events.XXXXXX")
  repo="$tmp_dir/repo"
  mkdir -p "$repo/scripts/org" "$repo/.ai/leases"
  cp "$ACQUIRE" "$repo/scripts/org/acquire-lease.sh"
  cp "$RELEASE" "$repo/scripts/org/release-lease.sh"
  chmod +x "$repo/scripts/org/acquire-lease.sh" "$repo/scripts/org/release-lease.sh"
  printf '%s\n%s\n' "$tmp_dir" "$repo"
}

assert_event_count() {
  local events_path="$1"
  local expected="$2"
  python3 - "$events_path" "$expected" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
expected = int(sys.argv[2])
actual = 0
if path.exists():
    actual = len([line for line in path.read_text(encoding="utf-8").splitlines() if line.strip()])
assert actual == expected, f"expected {expected} event(s), got {actual}"
PY
}

test_acquire_emits_lease_acquired_event() {
  local fixture tmp_dir repo lease_id events_path
  fixture=$(setup_repo_fixture)
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  events_path="$repo/.ai/EVENTS.jsonl"

  lease_id=$("$repo/scripts/org/acquire-lease.sh" --task-id T-EVENT-1 --actor-role codex --actor-id kernel --allowed-paths "src/auth/" --branch feature/lease-events)

  assert_exists "$events_path" "acquire should create event log"
  assert_event_count "$events_path" 1
  python3 - "$events_path" "$lease_id" <<'PY'
import json
import sys

events_path, lease_id = sys.argv[1:3]
with open(events_path, "r", encoding="utf-8") as handle:
    event = json.loads(handle.readline())

assert event["schema_version"] == "orgos.event.v1"
assert event["event_type"] == "LeaseAcquired"
assert event["type"] == "LeaseAcquired"
assert event["source"] == "scripts/org/acquire-lease.sh"
assert event["lease_id"] == lease_id
assert event["task_id"] == "T-EVENT-1"
assert event["actor"] == {"id": "kernel", "role": "codex"}
assert event["allowed_paths"] == ["src/auth/"]
assert event["lease_status"] == "active"
assert event["branch"] == "feature/lease-events"
assert event["lease"]["acquired_at"]
assert event["lease"]["expires_at"]
assert event["occurred_at"]
PY
  rm -rf "$tmp_dir"
}

test_release_emits_lease_released_event() {
  local fixture tmp_dir repo lease_id released_path events_path
  fixture=$(setup_repo_fixture)
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  events_path="$repo/.ai/EVENTS.jsonl"

  lease_id=$("$repo/scripts/org/acquire-lease.sh" --task-id T-EVENT-2 --actor-role manager --actor-id lead --allowed-paths "docs/")
  released_path=$("$repo/scripts/org/release-lease.sh" "$lease_id" --reason cancelled)

  assert_exists "$released_path" "release should write released lease"
  assert_event_count "$events_path" 2
  python3 - "$events_path" "$lease_id" <<'PY'
import json
import sys

events_path, lease_id = sys.argv[1:3]
with open(events_path, "r", encoding="utf-8") as handle:
    events = [json.loads(line) for line in handle if line.strip()]

assert [event["event_type"] for event in events] == ["LeaseAcquired", "LeaseReleased"]
released = events[1]
assert released["type"] == "LeaseReleased"
assert released["source"] == "scripts/org/release-lease.sh"
assert released["lease_id"] == lease_id
assert released["task_id"] == "T-EVENT-2"
assert released["actor"] == {"id": "lead", "role": "manager"}
assert released["allowed_paths"] == ["docs/"]
assert released["lease_status"] == "released"
assert released["release_reason"] == "cancelled"
assert released["lease"]["released_at"]
PY
  rm -rf "$tmp_dir"
}

test_failed_acquire_does_not_emit_event() {
  local fixture tmp_dir repo events_path stderr_path status
  fixture=$(setup_repo_fixture)
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  events_path="$repo/.ai/EVENTS.jsonl"
  stderr_path="$tmp_dir/stderr.log"

  "$repo/scripts/org/acquire-lease.sh" --task-id T-EVENT-3 --actor-role codex --actor-id kernel --allowed-paths "src/auth/" >/dev/null
  set +e
  "$repo/scripts/org/acquire-lease.sh" --task-id T-EVENT-4 --actor-role codex --actor-id kernel --allowed-paths "src/auth/login.ts" >/dev/null 2>"$stderr_path"
  status=$?
  set -e

  [ "$status" -eq 3 ] || fail "conflicting acquire should exit 3, got $status"
  assert_event_count "$events_path" 1
  python3 - "$events_path" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    events = [json.loads(line) for line in handle if line.strip()]
assert events[0]["event_type"] == "LeaseAcquired"
assert events[0]["task_id"] == "T-EVENT-3"
PY
  rm -rf "$tmp_dir"
}

test_failed_release_does_not_emit_event_log() {
  local fixture tmp_dir repo events_path stderr_path status
  fixture=$(setup_repo_fixture)
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  events_path="$repo/.ai/EVENTS.jsonl"
  stderr_path="$tmp_dir/stderr.log"

  set +e
  "$repo/scripts/org/release-lease.sh" LS-DOES-NOT-EXIST >/dev/null 2>"$stderr_path"
  status=$?
  set -e

  [ "$status" -eq 1 ] || fail "missing release should exit 1, got $status"
  assert_not_exists "$events_path" "failed release should not create event log"
  rm -rf "$tmp_dir"
}

run_test() {
  local name="$1"
  current_test_failed=0
  set +e
  "$name"
  local status=$?
  set -e

  if [ "$status" -eq 0 ] && [ "$current_test_failed" -eq 0 ]; then
    pass_count=$((pass_count + 1))
    printf 'ok - %s\n' "$name"
  else
    fail_count=$((fail_count + 1))
    printf 'not ok - %s\n' "$name" >&2
  fi
}

main() {
  case "${1:-}" in
    --only)
      shift
      run_test "$1"
      ;;
    "")
      run_test test_acquire_emits_lease_acquired_event
      run_test test_release_emits_lease_released_event
      run_test test_failed_acquire_does_not_emit_event
      run_test test_failed_release_does_not_emit_event_log
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac

  printf 'Lease event tests: %s passed, %s failed\n' "$pass_count" "$fail_count"
  [ "$fail_count" -eq 0 ]
}

main "$@"
