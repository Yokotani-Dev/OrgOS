#!/usr/bin/env bash
# Program event JSONL append and hash-chain tests.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
APPEND=${APPEND:-"$REPO_ROOT/scripts/org/append-event.py"}
SCHEMA=${SCHEMA:-"$REPO_ROOT/.claude/schemas/orgos-event.v1.json"}

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

assert_contains() {
  local path="$1"
  local needle="$2"
  local msg="$3"
  grep -Fq "$needle" "$path" || fail "$msg: expected '$needle' in $path"
}

setup_fixture() {
  local tmp_dir repo
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-events-append.XXXXXX")
  repo="$tmp_dir/repo"
  mkdir -p "$repo/scripts/org" "$repo/.claude/schemas"
  cp "$APPEND" "$repo/scripts/org/append-event.py"
  cp "$SCHEMA" "$repo/.claude/schemas/orgos-event.v1.json"
  chmod +x "$repo/scripts/org/append-event.py"
  printf '%s\n%s\n' "$tmp_dir" "$repo"
}

append_fixture_event() {
  local repo="$1"
  local event_type="$2"
  local ts="$3"
  local payload
  payload=${4:-'{}'}

  (
    cd "$repo"
    python3 scripts/org/append-event.py \
      --event-type "$event_type" \
      --task-id T-EVENTS-1 \
      --actor-role mock \
      --actor-id test \
      --payload-json "$payload" \
      --ts "$ts"
  )
}

test_event_schema_valid_json_and_enum() {
  python3 - "$SCHEMA" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    schema = json.load(handle)

required = set(schema["required"])
for field in ("event_id", "ts", "event_type", "task_id", "actor", "payload", "prev_hash", "hash"):
    assert field in required

event_types = schema["properties"]["event_type"]["enum"]
assert len(event_types) == 15
for event_type in (
    "TaskCreated",
    "TaskUpdated",
    "LeaseAcquired",
    "LeaseReleased",
    "WorkerStarted",
    "WorkerFinished",
    "ArtifactCollected",
    "VerificationPassed",
    "CommitIntegrated",
    "PolicyViolationDetected",
):
    assert event_type in event_types
PY
}

test_append_creates_monthly_jsonl() {
  local fixture tmp_dir repo events_path
  fixture=$(setup_fixture)
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  events_path="$repo/.ai/events/events-202605.jsonl"

  append_fixture_event "$repo" TaskCreated "2026-05-17T01:02:03Z" '{"title":"demo"}' >/dev/null

  assert_exists "$events_path" "append should create monthly events file"
  [ "$(wc -l < "$events_path" | tr -d ' ')" = "1" ] || fail "events file should contain one line"
  python3 - "$events_path" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    event = json.loads(handle.readline())

assert event["schema_version"] == "orgos-event.v1"
assert event["event_type"] == "TaskCreated"
assert event["payload"] == {"title": "demo"}
assert event["prev_hash"] == "0" * 64
assert len(event["hash"]) == 64
PY
  rm -rf "$tmp_dir"
}

test_append_hash_chain_links_events() {
  local fixture tmp_dir repo events_path
  fixture=$(setup_fixture)
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  events_path="$repo/.ai/events/events-202605.jsonl"

  append_fixture_event "$repo" TaskCreated "2026-05-17T01:02:03Z" >/dev/null
  append_fixture_event "$repo" TaskUpdated "2026-05-17T01:03:03Z" '{"status":"in_progress"}' >/dev/null

  python3 - "$events_path" <<'PY'
import hashlib
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    events = [json.loads(line) for line in handle if line.strip()]

assert len(events) == 2
for event in events:
    without_hash = {key: value for key, value in event.items() if key != "hash"}
    canonical = json.dumps(without_hash, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    assert event["hash"] == hashlib.sha256(canonical).hexdigest()
assert events[1]["prev_hash"] == events[0]["hash"]
PY
  rm -rf "$tmp_dir"
}

test_append_rejects_invalid_event_type() {
  local fixture tmp_dir repo stderr_path status
  fixture=$(setup_fixture)
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  stderr_path="$tmp_dir/stderr.log"

  set +e
  (
    cd "$repo"
    python3 scripts/org/append-event.py \
      --event-type Nope \
      --task-id T-EVENTS-1 \
      --actor-role mock \
      --actor-id test \
      --ts "2026-05-17T01:02:03Z"
  ) 2>"$stderr_path"
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "invalid event type should fail"
  assert_contains "$stderr_path" "invalid choice" "argparse should report invalid event type"
  [ ! -e "$repo/.ai/events/events-202605.jsonl" ] || fail "failed append should not create event file"
  rm -rf "$tmp_dir"
}

test_append_rejects_invalid_payload_json() {
  local fixture tmp_dir repo stderr_path status
  fixture=$(setup_fixture)
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  stderr_path="$tmp_dir/stderr.log"

  set +e
  append_fixture_event "$repo" TaskCreated "2026-05-17T01:02:03Z" '[]' >/dev/null 2>"$stderr_path"
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "array payload should fail"
  assert_contains "$stderr_path" "payload must be a JSON object" "payload validation should report object requirement"
  rm -rf "$tmp_dir"
}

test_append_links_across_month_files() {
  local fixture tmp_dir repo may_path june_path
  fixture=$(setup_fixture)
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  may_path="$repo/.ai/events/events-202605.jsonl"
  june_path="$repo/.ai/events/events-202606.jsonl"

  append_fixture_event "$repo" WorkerStarted "2026-05-31T23:59:59Z" >/dev/null
  append_fixture_event "$repo" WorkerFinished "2026-06-01T00:00:01Z" >/dev/null

  python3 - "$may_path" "$june_path" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    may = json.loads(handle.readline())
with open(sys.argv[2], "r", encoding="utf-8") as handle:
    june = json.loads(handle.readline())

assert june["prev_hash"] == may["hash"]
PY
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
      run_test test_event_schema_valid_json_and_enum
      run_test test_append_creates_monthly_jsonl
      run_test test_append_hash_chain_links_events
      run_test test_append_rejects_invalid_event_type
      run_test test_append_rejects_invalid_payload_json
      run_test test_append_links_across_month_files
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac

  printf 'Events append tests: %s passed, %s failed\n' "$pass_count" "$fail_count"
  [ "$fail_count" -eq 0 ]
}

main "$@"
