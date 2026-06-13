#!/usr/bin/env bash
# Integrator CommitIntegrated event tests
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
INTEGRATOR=${INTEGRATOR:-"$REPO_ROOT/scripts/org/integrator-commit.sh"}
VERIFIER=${VERIFIER:-"$REPO_ROOT/scripts/org/verify-artifact-manifest.py"}

pass_count=0
fail_count=0
current_test_failed=0

fail() {
  printf 'not ok - %s\n' "$1" >&2
  current_test_failed=1
  return 1
}

setup_repo_fixture() {
  local task_id="$1"
  local tmp_dir repo worktree branch
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-integrator-events.XXXXXX")
  repo="$tmp_dir/repo"
  worktree="$repo/.worktrees/$task_id"
  branch="task/$task_id-fixture"

  mkdir -p "$repo/scripts/org" "$repo/.ai/_machine/queue/integration/pending"
  git -C "$repo" init --quiet --initial-branch=main
  git -C "$repo" config user.name "Test User"
  git -C "$repo" config user.email "test@example.invalid"

  cp "$INTEGRATOR" "$repo/scripts/org/integrator-commit.sh"
  cp "$VERIFIER" "$repo/scripts/org/verify-artifact-manifest.py"
  cat > "$repo/scripts/org/append-event.py" <<'PY'
#!/usr/bin/env python3
import argparse
import json
import sys
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
  chmod +x "$repo/scripts/org/integrator-commit.sh" "$repo/scripts/org/verify-artifact-manifest.py" "$repo/scripts/org/append-event.py"

  printf 'base\n' > "$repo/README.md"
  git -C "$repo" add README.md scripts/org/integrator-commit.sh scripts/org/verify-artifact-manifest.py scripts/org/append-event.py
  git -C "$repo" commit --quiet -m "initial"
  git -C "$repo" worktree add --quiet -b "$branch" "$worktree" main

  printf '%s\n%s\n%s\n%s\n' "$tmp_dir" "$repo" "$worktree" "$branch"
}

write_manifest() {
  local repo="$1"
  local task_id="$2"
  local manifest_dir="$repo/.ai/_machine/artifacts/$task_id/20260515T000000Z-$task_id-event"
  mkdir -p "$manifest_dir/logs"
  printf 'stdout\n' > "$manifest_dir/logs/stdout.log"
  python3 - "$manifest_dir" "$task_id" <<'PY'
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

manifest_dir = Path(sys.argv[1])
task_id = sys.argv[2]
stdout_path = manifest_dir / "logs" / "stdout.log"
content = stdout_path.read_bytes()
payload = {
    "schema_version": "orgos.artifact_manifest.v1",
    "project_id": "orgos-test",
    "task_id": task_id,
    "run_id": f"20260515T000000Z-{task_id}-event",
    "created_at": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
    "repo": {"root": str(manifest_dir.parent.parent.parent.parent), "head": "test"},
    "actor": {"role": "test", "id": "kernel"},
    "execution": {"status": "completed"},
    "artifacts": [
        {
            "kind": "stdout",
            "artifact_path": "logs/stdout.log",
            "source_path": "stdout.log",
            "required": True,
            "status": "captured",
            "size_bytes": len(content),
            "sha256": hashlib.sha256(content).hexdigest(),
        }
    ],
    "verification": {"verified": True},
}
with (manifest_dir / "artifact_manifest.json").open("w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
print(manifest_dir / "artifact_manifest.json")
PY
}

write_queue_item() {
  local repo="$1"
  local worktree="$2"
  local branch="$3"
  local task_id="$4"
  local manifest="$5"
  local target_branch="$6"
  local base_commit expected_head queue_path
  base_commit=$(git -C "$worktree" rev-parse main)
  expected_head=$(git -C "$worktree" rev-parse HEAD)
  queue_path="$repo/.ai/_machine/queue/integration/pending/$task_id.json"
  python3 - "$queue_path" "$task_id" "$worktree" "$branch" "$base_commit" "$expected_head" "$manifest" "$target_branch" <<'PY'
import json
import sys
from datetime import datetime, timedelta, timezone

queue_path, task_id, worktree, branch, base_commit, expected_head, manifest, target_branch = sys.argv[1:9]
now = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
item = {
    "schema_version": "orgos.integration_queue.v1",
    "item_id": f"IQ-20260515T000000Z-{task_id}-1234abcd",
    "task_id": task_id,
    "project_id": "orgos-test",
    "status": "pending",
    "created_at": now,
    "created_by": {"role": "manager", "id": "test", "session_id": ""},
    "priority": 50,
    "dependencies": {"tasks": [], "queue_items": []},
    "worktree": {
        "path": worktree,
        "branch": branch,
        "base_branch": "main",
        "base_commit": base_commit,
        "expected_head": expected_head,
    },
    "scope": {
        "allowed_paths": ["README.md"],
        "prohibited_paths": [],
        "diff_budget": {"max_files": 10, "max_lines": 5000},
    },
    "artifacts": {"artifact_manifest": manifest, "diff_patch": "", "handoff": ""},
    "verification": {
        "required": True,
        "status": "passed",
        "commands": [],
        "artifacts": [],
        "passed_at": now,
    },
    "approvals": {"plan_id": "", "approval_id": "", "approval_hash": ""},
    "commit": {
        "target_branch": target_branch,
        "message": f"test: integrate {task_id}",
        "author_name": "OrgOS Integrator",
        "author_email": "orgos-integrator@local",
        "trailers": {"OrgOS-Task": task_id},
    },
    "attempts": {"count": 0, "max": 3, "last_attempt_at": None, "last_error": None},
    "retention": {
        "keep_until": (datetime.now(timezone.utc) + timedelta(days=90)).isoformat(timespec="seconds").replace("+00:00", "Z")
    },
}
with open(queue_path, "w", encoding="utf-8") as handle:
    json.dump(item, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
}

test_integrator_appends_commit_integrated_event() {
  local task_id="T-TEST-EVENT-1"
  local fixture tmp_dir repo worktree branch manifest output commit_sha
  fixture=$(setup_repo_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  worktree=$(printf '%s\n' "$fixture" | sed -n '3p')
  branch=$(printf '%s\n' "$fixture" | sed -n '4p')
  manifest=$(write_manifest "$repo" "$task_id")
  printf 'event integrated\n' > "$worktree/README.md"
  write_queue_item "$repo" "$worktree" "$branch" "$task_id" "$manifest" "main"

  output=$("$repo/scripts/org/integrator-commit.sh" --task-id "$task_id")
  commit_sha=$(git -C "$worktree" rev-parse HEAD)

  printf '%s\n' "$output" | grep -Eq '^[0-9a-f]{40}$' || fail "integrator should print commit sha"
  python3 - "$repo/.ai/EVENTS.jsonl" "$task_id" "$commit_sha" <<'PY'
import json
import re
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    events = [json.loads(line) for line in handle if line.strip()]
assert len(events) == 1
event = events[0]
assert event["event_type"] == "CommitIntegrated"
assert event["task_id"] == sys.argv[2]
assert event["actor"] == {"id": "integrator-commit.sh", "role": "integrator"}
assert event["payload"]["commit_sha"] == sys.argv[3]
assert event["payload"]["target_branch"] == "main"
assert re.match(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$", event["payload"]["integrated_at"])
PY
  rm -rf "$tmp_dir"
}

test_integrator_event_uses_queue_target_branch() {
  local task_id="T-TEST-EVENT-2"
  local fixture tmp_dir repo worktree branch manifest
  fixture=$(setup_repo_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  worktree=$(printf '%s\n' "$fixture" | sed -n '3p')
  branch=$(printf '%s\n' "$fixture" | sed -n '4p')
  manifest=$(write_manifest "$repo" "$task_id")
  printf 'release event\n' > "$worktree/README.md"
  write_queue_item "$repo" "$worktree" "$branch" "$task_id" "$manifest" "release/test"

  "$repo/scripts/org/integrator-commit.sh" --task-id "$task_id" >/dev/null

  python3 - "$repo/.ai/EVENTS.jsonl" "$task_id" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    events = [json.loads(line) for line in handle if line.strip()]
assert len(events) == 1
assert events[0]["event_type"] == "CommitIntegrated"
assert events[0]["task_id"] == sys.argv[2]
assert events[0]["payload"]["target_branch"] == "release/test"
PY
  rm -rf "$tmp_dir"
}

test_integrator_event_fallback_when_appender_absent() {
  local task_id="T-TEST-EVENT-3"
  local fixture tmp_dir repo worktree branch manifest
  fixture=$(setup_repo_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  worktree=$(printf '%s\n' "$fixture" | sed -n '3p')
  branch=$(printf '%s\n' "$fixture" | sed -n '4p')
  manifest=$(write_manifest "$repo" "$task_id")
  rm "$repo/scripts/org/append-event.py"
  printf 'fallback event\n' > "$worktree/README.md"
  write_queue_item "$repo" "$worktree" "$branch" "$task_id" "$manifest" "main"

  "$repo/scripts/org/integrator-commit.sh" --task-id "$task_id" >/dev/null

  python3 - "$repo/.ai/EVENTS.jsonl" "$task_id" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    events = [json.loads(line) for line in handle if line.strip()]
assert len(events) == 1
assert events[0]["event_type"] == "CommitIntegrated"
assert events[0]["task_id"] == sys.argv[2]
assert events[0]["payload"]["target_branch"] == "main"
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
  run_test test_integrator_appends_commit_integrated_event
  run_test test_integrator_event_uses_queue_target_branch
  run_test test_integrator_event_fallback_when_appender_absent
  printf 'Integrator event tests: %s passed, %s failed\n' "$pass_count" "$fail_count"
  [ "$fail_count" -eq 0 ]
}

main "$@"
