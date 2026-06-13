#!/usr/bin/env bash
# Artifact collection event emission tests
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
COLLECTOR=${COLLECTOR:-"$REPO_ROOT/scripts/org/collect-artifacts.sh"}

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

setup_event_fixture() {
  local task_id="$1"
  local tmp_dir repo worktree artifact_dir stdout_path stderr_path last_msg_path

  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-collect-events.XXXXXX")
  repo="$tmp_dir/repo"
  worktree="$repo/.worktrees/$task_id"
  artifact_dir="$repo/.ai/_machine/artifacts/$task_id/20260517T000000Z-$task_id-1234abcd"
  stdout_path="$tmp_dir/stdout.log"
  stderr_path="$tmp_dir/stderr.log"
  last_msg_path="$tmp_dir/output-last-message.txt"

  git clone --quiet "$REPO_ROOT" "$repo"
  git -C "$repo" worktree add --quiet "$worktree" HEAD
  cp "$COLLECTOR" "$repo/scripts/org/collect-artifacts.sh"
  # NOTE (2026-06-11, audit P2-7): the original mock read a full event JSON from
  # stdin, which matched a pre-kernel-v2 append-event contract. The real
  # scripts/org/append-event.py is now a CLI (--event-type/--task-id/
  # --actor-role/--actor-id/--payload-json) writing a hash-chained monthly
  # ledger. This mock mirrors the current CLI contract (same pattern as
  # tests/kernel/test-integrator-events.sh) and flattens output into
  # .ai/EVENTS.jsonl for assertion.
  cat > "$repo/scripts/org/append-event.py" <<'PY'
#!/usr/bin/env python3
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--event-type", required=True)
parser.add_argument("--task-id", required=True)
parser.add_argument("--actor-role", required=True)
parser.add_argument("--actor-id", required=True)
parser.add_argument("--payload-json", default="{}")
args = parser.parse_args()

event = {
    "event_type": args.event_type,
    "task_id": args.task_id,
    "actor": {"role": args.actor_role, "id": args.actor_id},
    "payload": json.loads(args.payload_json),
}
root = Path(__file__).resolve().parents[2]
events_path = root / ".ai" / "EVENTS.jsonl"
events_path.parent.mkdir(parents=True, exist_ok=True)
with events_path.open("a", encoding="utf-8") as handle:
    json.dump(event, handle, sort_keys=True)
    handle.write("\n")
PY
  chmod +x "$repo/scripts/org/collect-artifacts.sh" "$repo/scripts/org/append-event.py"
  printf 'mock stdout\n' > "$stdout_path"
  printf 'mock stderr\n' > "$stderr_path"
  printf 'mock final message\n' > "$last_msg_path"

  printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' \
    "$tmp_dir" "$repo" "$worktree" "$artifact_dir" "$stdout_path" "$stderr_path" "$last_msg_path"
}

run_collect_with_events() {
  local repo="$1"
  local task_id="$2"
  local worktree="$3"
  local artifact_dir="$4"
  local stdout_path="$5"
  local stderr_path="$6"
  local last_msg_path="$7"

  (
    cd "$repo"
    "$repo/scripts/org/collect-artifacts.sh" \
        --task-id "$task_id" \
        --run-id "20260517T000000Z-$task_id-1234abcd" \
        --worktree-path "$worktree" \
        --artifact-dir "$artifact_dir" \
        --stdout-source "$stdout_path" \
        --stderr-source "$stderr_path" \
        --last-message-source "$last_msg_path" \
        --actor-role mock \
        --actor-id test
  )
}

test_collect_appends_artifact_collected_event() {
  local task_id="T-COLLECT-EVENT"
  local fixture tmp_dir repo worktree artifact_dir stdout_path stderr_path last_msg_path events_path manifest_path
  fixture=$(setup_event_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  worktree=$(printf '%s\n' "$fixture" | sed -n '3p')
  artifact_dir=$(printf '%s\n' "$fixture" | sed -n '4p')
  stdout_path=$(printf '%s\n' "$fixture" | sed -n '5p')
  stderr_path=$(printf '%s\n' "$fixture" | sed -n '6p')
  last_msg_path=$(printf '%s\n' "$fixture" | sed -n '7p')
  events_path="$repo/.ai/EVENTS.jsonl"
  manifest_path="$artifact_dir/artifact_manifest.json"

  run_collect_with_events "$repo" "$task_id" "$worktree" "$artifact_dir" "$stdout_path" "$stderr_path" "$last_msg_path"

  assert_exists "$events_path" "collector should append event"
  python3 - "$events_path" "$task_id" "20260517T000000Z-$task_id-1234abcd" "$manifest_path" <<'PY' || fail "event should match manifest payload"
import json
import sys
from pathlib import Path

events_path, task_id, run_id, manifest_path = sys.argv[1:5]
with open(events_path, "r", encoding="utf-8") as handle:
    events = [json.loads(line) for line in handle if line.strip()]
assert len(events) == 1
event = events[0]
assert event["event_type"] == "ArtifactCollected"
assert event["task_id"] == task_id
payload = event["payload"]
assert payload["run_id"] == run_id
assert payload["manifest_path"] == Path(manifest_path).resolve().as_posix()
with open(manifest_path, "r", encoding="utf-8") as handle:
    manifest = json.load(handle)
assert payload["artifact_count"] == len(manifest["artifacts"])
PY
  rm -rf "$tmp_dir"
}

test_collect_does_not_append_event_when_collection_fails() {
  local task_id="T-COLLECT-EVENT-FAIL"
  local fixture tmp_dir repo worktree artifact_dir stdout_path stderr_path last_msg_path events_path status
  fixture=$(setup_event_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  worktree=$(printf '%s\n' "$fixture" | sed -n '3p')
  artifact_dir=$(printf '%s\n' "$fixture" | sed -n '4p')
  stdout_path=$(printf '%s\n' "$fixture" | sed -n '5p')
  stderr_path=$(printf '%s\n' "$fixture" | sed -n '6p')
  last_msg_path=$(printf '%s\n' "$fixture" | sed -n '7p')
  events_path="$repo/.ai/EVENTS.jsonl"
  rm "$stdout_path"

  set +e
  run_collect_with_events "$repo" "$task_id" "$worktree" "$artifact_dir" "$stdout_path" "$stderr_path" "$last_msg_path" >/dev/null 2>&1
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "collector should fail when a required source is missing"
  assert_not_exists "$events_path" "collector should not append event after failed collection"
  rm -rf "$tmp_dir"
}

run_test() {
  local name="$1"
  current_test_failed=0
  "$name" || current_test_failed=1
  if [ "$current_test_failed" -eq 0 ]; then
    pass_count=$((pass_count + 1))
    printf 'ok - %s\n' "$name"
  else
    fail_count=$((fail_count + 1))
    printf 'not ok - %s\n' "$name" >&2
  fi
}

main() {
  run_test test_collect_appends_artifact_collected_event
  run_test test_collect_does_not_append_event_when_collection_fails

  printf 'collect events tests: %s passed, %s failed\n' "$pass_count" "$fail_count"
  [ "$fail_count" -eq 0 ]
}

main "$@"
