#!/usr/bin/env bash
# Week 2 integrator queue and commit gate tests
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
REQUEST=${REQUEST:-"$REPO_ROOT/scripts/org/request-integration.sh"}
INTEGRATOR=${INTEGRATOR:-"$REPO_ROOT/scripts/org/integrator-commit.sh"}
POLICY=${POLICY:-"$REPO_ROOT/.claude/hooks/pretool_policy.py"}
SCHEMA=${SCHEMA:-"$REPO_ROOT/.claude/schemas/integration-queue.v1.json"}

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

assert_contains() {
  local path="$1"
  local needle="$2"
  local msg="$3"
  grep -Fq "$needle" "$path" || fail "$msg: expected '$needle' in $path"
}

setup_repo_fixture() {
  local task_id="$1"
  local tmp_dir repo worktree branch
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-week2-integrator.XXXXXX")
  repo="$tmp_dir/repo"
  worktree="$repo/.worktrees/$task_id"
  branch="task/$task_id-fixture"

  mkdir -p "$repo"
  git -C "$repo" init --quiet --initial-branch=main
  git -C "$repo" config user.name "Test User"
  git -C "$repo" config user.email "test@example.invalid"
  mkdir -p "$repo/scripts/org" "$repo/.claude/hooks" "$repo/.claude/schemas" "$repo/.ai/_machine/queue/integration"
  cp "$REQUEST" "$repo/scripts/org/request-integration.sh"
  cp "$INTEGRATOR" "$repo/scripts/org/integrator-commit.sh"
  cp "$REPO_ROOT/scripts/org/verify-artifact-manifest.py" "$repo/scripts/org/verify-artifact-manifest.py"
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
  cp "$POLICY" "$repo/.claude/hooks/pretool_policy.py"
  cp "$REPO_ROOT/.claude/hooks/policy_core.py" "$repo/.claude/hooks/policy_core.py"
  cp "$SCHEMA" "$repo/.claude/schemas/integration-queue.v1.json"
  chmod +x "$repo/scripts/org/request-integration.sh" "$repo/scripts/org/integrator-commit.sh" "$repo/scripts/org/verify-artifact-manifest.py" "$repo/scripts/org/append-event.py"

  printf 'base\n' > "$repo/README.md"
  git -C "$repo" add README.md scripts/org/request-integration.sh scripts/org/integrator-commit.sh scripts/org/verify-artifact-manifest.py scripts/org/append-event.py .claude/hooks/pretool_policy.py .claude/hooks/policy_core.py .claude/schemas/integration-queue.v1.json
  git -C "$repo" commit --quiet -m "initial"
  git -C "$repo" worktree add --quiet -b "$branch" "$worktree" main

  printf '%s\n%s\n%s\n%s\n' "$tmp_dir" "$repo" "$worktree" "$branch"
}

write_manifest() {
  local repo="$1"
  local task_id="$2"
  local manifest_dir="$repo/.ai/_machine/artifacts/$task_id/20260515T000000Z-$task_id-1234abcd"
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
    "run_id": f"20260515T000000Z-{task_id}-1234abcd",
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

assert_queue_schema_valid_json() {
  python3 - "$SCHEMA" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)
required = {"schema_version", "item_id", "task_id", "worktree", "scope", "artifacts", "verification", "commit"}
missing = required.difference(data.get("properties", {}))
if missing:
    print(f"schema missing properties: {sorted(missing)}", file=sys.stderr)
    raise SystemExit(1)
PY
}

test_request_integration_creates_pending() {
  local task_id="T-TEST-1"
  local fixture tmp_dir repo worktree branch manifest queue_path
  fixture=$(setup_repo_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  worktree=$(printf '%s\n' "$fixture" | sed -n '3p')
  branch=$(printf '%s\n' "$fixture" | sed -n '4p')
  manifest=$(write_manifest "$repo" "$task_id")
  printf 'change\n' > "$worktree/README.md"

  queue_path=$("$repo/scripts/org/request-integration.sh" \
    --task-id "$task_id" \
    --worktree-path "$worktree" \
    --branch "$branch" \
    --base-branch main \
    --artifact-manifest "$manifest" \
    --commit-message "test: integrate $task_id" \
    --allowed-paths "README.md")

  assert_exists "$queue_path" "request-integration should create pending item"
  assert_queue_schema_valid_json
  python3 - "$queue_path" "$task_id" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)
assert data["schema_version"] == "orgos.integration_queue.v1"
assert data["task_id"] == sys.argv[2]
assert data["status"] == "pending"
assert "README.md" in data["scope"]["allowed_paths"]
PY
  rm -rf "$tmp_dir"
}

test_request_integration_explicit_allowed_paths_arg() {
  local task_id="T-TEST-1A"
  local fixture tmp_dir repo worktree branch manifest queue_path
  fixture=$(setup_repo_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  worktree=$(printf '%s\n' "$fixture" | sed -n '3p')
  branch=$(printf '%s\n' "$fixture" | sed -n '4p')
  manifest=$(write_manifest "$repo" "$task_id")
  printf 'change\n' > "$worktree/README.md"

  queue_path=$("$repo/scripts/org/request-integration.sh" \
    --task-id "$task_id" \
    --worktree-path "$worktree" \
    --branch "$branch" \
    --base-branch main \
    --artifact-manifest "$manifest" \
    --commit-message "test: explicit allowed paths" \
    --allowed-paths "README.md, src/")

  python3 - "$queue_path" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)
assert data["scope"]["allowed_paths"] == ["README.md", "src/"]
assert data["scope"]["diff_budget"] == {"max_files": 10, "max_lines": 5000}
PY
  rm -rf "$tmp_dir"
}

test_request_integration_lease_lookup_succeeds() {
  local task_id="T-TEST-1B"
  local fixture tmp_dir repo worktree branch manifest queue_path
  fixture=$(setup_repo_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  worktree=$(printf '%s\n' "$fixture" | sed -n '3p')
  branch=$(printf '%s\n' "$fixture" | sed -n '4p')
  manifest=$(write_manifest "$repo" "$task_id")
  printf 'change\n' > "$worktree/README.md"
  mkdir -p "$repo/.ai/_machine/leases"
  python3 - "$repo/.ai/_machine/leases/lease-$task_id.json" "$task_id" <<'PY'
import json
import sys
from datetime import datetime, timedelta, timezone

payload = {
    "schema_version": "orgos.lease.v1",
    "lease_id": "LS-test",
    "task_id": sys.argv[2],
    "status": "active",
    "allowed_paths": ["docs/kernel-v2/"],
    "expires_at": (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat(timespec="seconds").replace("+00:00", "Z"),
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(payload, handle)
PY

  queue_path=$("$repo/scripts/org/request-integration.sh" \
    --task-id "$task_id" \
    --worktree-path "$worktree" \
    --branch "$branch" \
    --base-branch main \
    --artifact-manifest "$manifest" \
    --commit-message "test: lease allowed paths")

  python3 - "$queue_path" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)
assert data["scope"]["allowed_paths"] == ["docs/kernel-v2/"]
assert data["scope"]["diff_budget"] == {"max_files": 10, "max_lines": 5000}
PY
  rm -rf "$tmp_dir"
}

test_request_integration_no_allowed_paths_no_lease_rejects() {
  local task_id="T-TEST-1C"
  local fixture tmp_dir repo worktree branch manifest stderr_path status
  fixture=$(setup_repo_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  worktree=$(printf '%s\n' "$fixture" | sed -n '3p')
  branch=$(printf '%s\n' "$fixture" | sed -n '4p')
  manifest=$(write_manifest "$repo" "$task_id")
  stderr_path="$tmp_dir/request-no-allowed.stderr"

  set +e
  "$repo/scripts/org/request-integration.sh" \
    --task-id "$task_id" \
    --worktree-path "$worktree" \
    --branch "$branch" \
    --base-branch main \
    --artifact-manifest "$manifest" \
    --commit-message "test: reject missing allowed paths" >/dev/null 2>"$stderr_path"
  status=$?
  set -e

  [ "$status" -eq 2 ] || fail "request-integration should exit 2 without allowed paths or active lease"
  assert_contains "$stderr_path" "allowed_paths required: provide --allowed-paths or have an active lease for this task" "missing allowed_paths should explain refusal"
  rm -rf "$tmp_dir"
}

test_request_integration_rejects_protected_branch() {
  local task_id="T-TEST-2"
  local fixture tmp_dir repo worktree manifest status
  fixture=$(setup_repo_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  worktree=$(printf '%s\n' "$fixture" | sed -n '3p')
  manifest=$(write_manifest "$repo" "$task_id")

  set +e
  "$repo/scripts/org/request-integration.sh" \
    --task-id "$task_id" \
    --worktree-path "$worktree" \
    --branch main \
    --base-branch main \
    --artifact-manifest "$manifest" \
    --commit-message "test: reject protected" \
    --allowed-paths "README.md" >/dev/null 2>&1
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "protected branch request should fail"
  rm -rf "$tmp_dir"
}

test_integrator_commit_success() {
  local task_id="T-TEST-3"
  local fixture tmp_dir repo worktree branch manifest queue_path output done_count head_msg commit_sha
  fixture=$(setup_repo_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  worktree=$(printf '%s\n' "$fixture" | sed -n '3p')
  branch=$(printf '%s\n' "$fixture" | sed -n '4p')
  manifest=$(write_manifest "$repo" "$task_id")
  printf 'integrated\n' > "$worktree/README.md"

  queue_path=$("$repo/scripts/org/request-integration.sh" \
    --task-id "$task_id" \
    --worktree-path "$worktree" \
    --branch "$branch" \
    --base-branch main \
    --artifact-manifest "$manifest" \
    --commit-message "test: integrate $task_id" \
    --allowed-paths "README.md")

  output=$("$repo/scripts/org/integrator-commit.sh" --task-id "$task_id")
  done_count=$(find "$repo/.ai/_machine/queue/integration/done" -name "$task_id.*.json" | wc -l | tr -d ' ')
  head_msg=$(git -C "$worktree" log -1 --pretty=%s)
  commit_sha=$(git -C "$worktree" rev-parse HEAD)

  [ "$done_count" -eq 1 ] || fail "integrator should move queue item to done"
  [ "$head_msg" = "test: integrate $task_id" ] || fail "integrator should create commit"
  assert_not_exists "$queue_path" "pending queue item should be consumed"
  printf '%s\n' "$output" | grep -Eq '^[0-9a-f]{40}$' || fail "integrator should print commit sha"
  python3 - "$repo/.ai/EVENTS.jsonl" "$task_id" "$commit_sha" <<'PY'
import json
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
assert event["payload"]["integrated_at"].endswith("Z")
PY
  rm -rf "$tmp_dir"
}

test_integrator_commit_blocks_without_manifest() {
  local task_id="T-TEST-4"
  local fixture tmp_dir repo worktree branch manifest queue_path status
  fixture=$(setup_repo_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  worktree=$(printf '%s\n' "$fixture" | sed -n '3p')
  branch=$(printf '%s\n' "$fixture" | sed -n '4p')
  manifest=$(write_manifest "$repo" "$task_id")
  printf 'integrated\n' > "$worktree/README.md"
  queue_path=$("$repo/scripts/org/request-integration.sh" \
    --task-id "$task_id" \
    --worktree-path "$worktree" \
    --branch "$branch" \
    --base-branch main \
    --artifact-manifest "$manifest" \
    --commit-message "test: missing manifest" \
    --allowed-paths "README.md")
  rm "$manifest"

  set +e
  "$repo/scripts/org/integrator-commit.sh" --queue-item "$queue_path" --task-id "$task_id" >/dev/null 2>&1
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "integrator should reject missing manifest"
  [ "$(find "$repo/.ai/_machine/queue/integration/failed" -name "$task_id.*.json" | wc -l | tr -d ' ')" -eq 1 ] || fail "failed item should be recorded"
  rm -rf "$tmp_dir"
}

test_integrator_commit_blocks_diff_outside_allowed_paths() {
  local task_id="T-TEST-5"
  local fixture tmp_dir repo worktree branch manifest queue_path output done_count
  fixture=$(setup_repo_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  worktree=$(printf '%s\n' "$fixture" | sed -n '3p')
  branch=$(printf '%s\n' "$fixture" | sed -n '4p')
  manifest=$(write_manifest "$repo" "$task_id")
  printf 'allowed\n' > "$worktree/README.md"
  queue_path=$("$repo/scripts/org/request-integration.sh" \
    --task-id "$task_id" \
    --worktree-path "$worktree" \
    --branch "$branch" \
    --base-branch main \
    --artifact-manifest "$manifest" \
    --commit-message "test: scope" \
    --allowed-paths "README.md")
  printf 'outside\n' > "$worktree/outside.txt"

  output=$("$repo/scripts/org/integrator-commit.sh" --task-id "$task_id")
  done_count=$(find "$repo/.ai/_machine/queue/integration/done" -name "$task_id.*.json" | wc -l | tr -d ' ')

  [ "$done_count" -eq 1 ] || fail "integrator should move queue item to done while outside paths are present"
  assert_not_exists "$queue_path" "pending queue item should be consumed"
  printf '%s\n' "$output" | grep -Eq '^[0-9a-f]{40}$' || fail "integrator should print commit sha"
  git -C "$worktree" show --name-only --pretty=format: HEAD | grep -Fxq "README.md" || fail "allowed path should be committed"
  ! git -C "$worktree" show --name-only --pretty=format: HEAD | grep -Fxq "outside.txt" || fail "outside path should not be committed"
  git -C "$worktree" status --porcelain --untracked-files=all | grep -Fq "outside.txt" || fail "outside path should remain untracked"
  rm -rf "$tmp_dir"
}

test_integrator_only_commits_allowed_paths_intersect() {
  local task_id="T-TEST-9"
  local fixture tmp_dir repo worktree branch manifest output done_count changed_names
  fixture=$(setup_repo_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  worktree=$(printf '%s\n' "$fixture" | sed -n '3p')
  branch=$(printf '%s\n' "$fixture" | sed -n '4p')
  manifest=$(write_manifest "$repo" "$task_id")
  printf 'allowed readme\n' > "$worktree/README.md"
  mkdir -p "$worktree/src"
  printf 'allowed source\n' > "$worktree/src/allowed.txt"

  "$repo/scripts/org/request-integration.sh" \
    --task-id "$task_id" \
    --worktree-path "$worktree" \
    --branch "$branch" \
    --base-branch main \
    --artifact-manifest "$manifest" \
    --commit-message "test: intersect $task_id" \
    --allowed-paths "README.md,src/" >/dev/null

  mkdir -p "$worktree/.ai/_machine/codex/AUDIT" "$worktree/.ai/_machine/sessions" "$worktree/.claude/state"
  printf 'audit\n' > "$worktree/.ai/_machine/codex/AUDIT/$task_id.log"
  printf 'session\n' > "$worktree/.ai/_machine/sessions/$task_id.jsonl"
  printf 'pretool\n' > "$worktree/.claude/state/pretool_$task_id.jsonl"
  printf 'outside\n' > "$worktree/outside.txt"

  output=$("$repo/scripts/org/integrator-commit.sh" --task-id "$task_id")
  done_count=$(find "$repo/.ai/_machine/queue/integration/done" -name "$task_id.*.json" | wc -l | tr -d ' ')
  changed_names=$(git -C "$worktree" show --name-only --pretty=format: HEAD)

  [ "$done_count" -eq 1 ] || fail "integrator should complete with irrelevant paths present"
  printf '%s\n' "$output" | grep -Eq '^[0-9a-f]{40}$' || fail "integrator should print commit sha"
  printf '%s\n' "$changed_names" | grep -Fxq "README.md" || fail "README.md should be committed"
  printf '%s\n' "$changed_names" | grep -Fxq "src/allowed.txt" || fail "allowed source should be committed"
  ! printf '%s\n' "$changed_names" | grep -Eq '^(\.ai/|\.claude/|outside\.txt$)' || fail "irrelevant paths should not be committed"
  git -C "$worktree" status --porcelain --untracked-files=all | grep -Fq ".ai/_machine/codex/AUDIT/$task_id.log" || fail "audit path should remain untracked"
  git -C "$worktree" status --porcelain --untracked-files=all | grep -Fq ".ai/_machine/sessions/$task_id.jsonl" || fail "session path should remain untracked"
  git -C "$worktree" status --porcelain --untracked-files=all | grep -Fq ".claude/state/pretool_$task_id.jsonl" || fail "pretool path should remain untracked"
  git -C "$worktree" status --porcelain --untracked-files=all | grep -Fq "outside.txt" || fail "outside path should remain untracked"
  rm -rf "$tmp_dir"
}

test_integrator_refuses_empty_intersect() {
  local task_id="T-TEST-10"
  local fixture tmp_dir repo worktree branch manifest queue_path stderr_path status
  fixture=$(setup_repo_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  worktree=$(printf '%s\n' "$fixture" | sed -n '3p')
  branch=$(printf '%s\n' "$fixture" | sed -n '4p')
  manifest=$(write_manifest "$repo" "$task_id")
  stderr_path="$tmp_dir/integrator-empty-intersect.stderr"
  printf 'allowed snapshot\n' > "$worktree/README.md"
  queue_path=$("$repo/scripts/org/request-integration.sh" \
    --task-id "$task_id" \
    --worktree-path "$worktree" \
    --branch "$branch" \
    --base-branch main \
    --artifact-manifest "$manifest" \
    --commit-message "test: empty intersect" \
    --allowed-paths "README.md")
  git -C "$worktree" checkout -- README.md
  mkdir -p "$worktree/.ai/_machine/codex/AUDIT"
  printf 'audit only\n' > "$worktree/.ai/_machine/codex/AUDIT/$task_id.log"

  set +e
  "$repo/scripts/org/integrator-commit.sh" --queue-item "$queue_path" --task-id "$task_id" >/dev/null 2>"$stderr_path"
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "integrator should reject empty allowed_paths intersect"
  assert_contains "$stderr_path" "no user diff within allowed_paths" "empty intersect should explain refusal"
  [ "$(find "$repo/.ai/_machine/queue/integration/failed" -name "$task_id.*.json" | wc -l | tr -d ' ')" -eq 1 ] || fail "failed empty-intersect item should be recorded"
  rm -rf "$tmp_dir"
}

test_integrator_ignores_queue_state_transitions() {
  local task_id="T-TEST-6"
  local fixture tmp_dir repo worktree branch manifest output done_count
  fixture=$(setup_repo_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  worktree=$(printf '%s\n' "$fixture" | sed -n '3p')
  branch=$(printf '%s\n' "$fixture" | sed -n '4p')
  manifest=$(write_manifest "$repo" "$task_id")
  printf 'integrated queue state\n' > "$worktree/README.md"

  "$repo/scripts/org/request-integration.sh" \
    --task-id "$task_id" \
    --worktree-path "$worktree" \
    --branch "$branch" \
    --base-branch main \
    --artifact-manifest "$manifest" \
    --commit-message "test: ignore queue state $task_id" \
    --allowed-paths "README.md" >/dev/null
  mkdir -p "$worktree/.ai/_machine/queue/integration/processing"
  printf '{"status":"processing"}\n' > "$worktree/.ai/_machine/queue/integration/processing/$task_id.json"

  output=$("$repo/scripts/org/integrator-commit.sh" --task-id "$task_id")
  done_count=$(find "$repo/.ai/_machine/queue/integration/done" -name "$task_id.*.json" | wc -l | tr -d ' ')

  [ "$done_count" -eq 1 ] || fail "integrator should move queue item to done with queue state present"
  printf '%s\n' "$output" | grep -Eq '^[0-9a-f]{40}$' || fail "integrator should print commit sha"
  ! git -C "$worktree" show --name-only --pretty=format: HEAD | grep -Fq ".ai/_machine/queue/integration/" || fail "queue state should not be committed"
  rm -rf "$tmp_dir"
}

test_integrator_ignores_leases_and_artifacts() {
  local task_id="T-TEST-7"
  local fixture tmp_dir repo worktree branch manifest output done_count
  fixture=$(setup_repo_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  worktree=$(printf '%s\n' "$fixture" | sed -n '3p')
  branch=$(printf '%s\n' "$fixture" | sed -n '4p')
  manifest=$(write_manifest "$repo" "$task_id")
  printf 'integrated internal state\n' > "$worktree/README.md"

  "$repo/scripts/org/request-integration.sh" \
    --task-id "$task_id" \
    --worktree-path "$worktree" \
    --branch "$branch" \
    --base-branch main \
    --artifact-manifest "$manifest" \
    --commit-message "test: ignore internal state $task_id" \
    --allowed-paths "README.md" >/dev/null
  mkdir -p "$worktree/.ai/_machine/leases" "$worktree/.ai/_machine/artifacts/$task_id" "$worktree/.ai/alerts"
  printf '{"holder":"integrator"}\n' > "$worktree/.ai/_machine/leases/$task_id.json"
  printf 'runtime artifact\n' > "$worktree/.ai/_machine/artifacts/$task_id/runtime.log"
  printf 'alert log\n' > "$worktree/.ai/alerts/$task_id.log"

  output=$("$repo/scripts/org/integrator-commit.sh" --task-id "$task_id")
  done_count=$(find "$repo/.ai/_machine/queue/integration/done" -name "$task_id.*.json" | wc -l | tr -d ' ')

  [ "$done_count" -eq 1 ] || fail "integrator should move queue item to done with internal state present"
  printf '%s\n' "$output" | grep -Eq '^[0-9a-f]{40}$' || fail "integrator should print commit sha"
  ! git -C "$worktree" show --name-only --pretty=format: HEAD | grep -Eq '^\.ai/(leases|artifacts|alerts)/' || fail "leases, artifacts, and alerts should not be committed"
  rm -rf "$tmp_dir"
}

test_integrator_ignores_uppercase_legacy_paths() {
  local task_id="T-TEST-7B"
  local fixture tmp_dir repo worktree branch manifest output done_count
  fixture=$(setup_repo_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  worktree=$(printf '%s\n' "$fixture" | sed -n '3p')
  branch=$(printf '%s\n' "$fixture" | sed -n '4p')
  manifest=$(write_manifest "$repo" "$task_id")
  printf 'integrated uppercase legacy artifacts\n' > "$worktree/README.md"

  "$repo/scripts/org/request-integration.sh" \
    --task-id "$task_id" \
    --worktree-path "$worktree" \
    --branch "$branch" \
    --base-branch main \
    --artifact-manifest "$manifest" \
    --commit-message "test: ignore uppercase legacy paths $task_id" \
    --allowed-paths "README.md" >/dev/null
  mkdir -p "$worktree/.ai/ARTIFACTS/$task_id/legacy" "$worktree/.ai/_machine/artifacts/$task_id/runtime"
  printf '{"legacy":true}\n' > "$worktree/.ai/ARTIFACTS/$task_id/legacy/artifact_manifest.json"
  printf 'runtime artifact\n' > "$worktree/.ai/_machine/artifacts/$task_id/runtime/output.log"

  output=$("$repo/scripts/org/integrator-commit.sh" --task-id "$task_id")
  done_count=$(find "$repo/.ai/_machine/queue/integration/done" -name "$task_id.*.json" | wc -l | tr -d ' ')

  [ "$done_count" -eq 1 ] || fail "integrator should move queue item to done with uppercase legacy artifacts present"
  printf '%s\n' "$output" | grep -Eq '^[0-9a-f]{40}$' || fail "integrator should print commit sha"
  ! git -C "$worktree" show --name-only --pretty=format: HEAD | grep -Eqi '^\.ai/_machine/artifacts/' || fail "artifact paths should not be committed regardless of case"
  rm -rf "$tmp_dir"
}

test_integrator_ignores_claude_state_file() {
  local task_id="T-TEST-8"
  local fixture tmp_dir repo worktree branch manifest output done_count
  fixture=$(setup_repo_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  worktree=$(printf '%s\n' "$fixture" | sed -n '3p')
  branch=$(printf '%s\n' "$fixture" | sed -n '4p')
  manifest=$(write_manifest "$repo" "$task_id")
  printf 'integrated claude state\n' > "$worktree/README.md"

  "$repo/scripts/org/request-integration.sh" \
    --task-id "$task_id" \
    --worktree-path "$worktree" \
    --branch "$branch" \
    --base-branch main \
    --artifact-manifest "$manifest" \
    --commit-message "test: ignore claude state $task_id" \
    --allowed-paths "README.md" >/dev/null
  mkdir -p "$worktree/.claude/state"
  printf 'pid=123 task_id=%s\n' "$task_id" > "$worktree/.claude/state/git.lock"

  output=$("$repo/scripts/org/integrator-commit.sh" --task-id "$task_id")
  done_count=$(find "$repo/.ai/_machine/queue/integration/done" -name "$task_id.*.json" | wc -l | tr -d ' ')

  [ "$done_count" -eq 1 ] || fail "integrator should move queue item to done with claude state present"
  printf '%s\n' "$output" | grep -Eq '^[0-9a-f]{40}$' || fail "integrator should print commit sha"
  ! git -C "$worktree" show --name-only --pretty=format: HEAD | grep -Fq ".claude/state/" || fail "claude state should not be committed"
  rm -rf "$tmp_dir"
}

test_integrator_env_prefix_does_not_bypass() {
  local tmp_dir fixture stderr_path status
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-week2-policy.XXXXXX")
  fixture="$tmp_dir/fixture.json"
  stderr_path="$tmp_dir/stderr.log"
  python3 - "$fixture" <<'PY'
import json
import sys
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(
        {
            "tool": "Bash",
            "command": "ORGOS_INTEGRATOR=1 git commit -m test",
            "path": "",
            "cwd": "/tmp/repo",
        },
        handle,
    )
PY
  set +e
  ORGOS_KERNEL_MODE_OVERRIDE=enforce python3 "$POLICY" --test-fixture "$fixture" 2>"$stderr_path"
  status=$?
  set -e
  [ "$status" -eq 2 ] || fail "KRT-011 env prefix bypass should be denied, got $status"
  assert_contains "$stderr_path" "ORGOS_POLICY_DENY" "KRT-011 policy should deny"
  assert_contains "$stderr_path" "IntegratorOnlyCommit" "KRT-011 should report IntegratorOnlyCommit"
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
      run_test test_request_integration_creates_pending
      run_test test_request_integration_explicit_allowed_paths_arg
      run_test test_request_integration_lease_lookup_succeeds
      run_test test_request_integration_no_allowed_paths_no_lease_rejects
      run_test test_request_integration_rejects_protected_branch
      run_test test_integrator_commit_success
      run_test test_integrator_commit_blocks_without_manifest
      run_test test_integrator_commit_blocks_diff_outside_allowed_paths
      run_test test_integrator_ignores_queue_state_transitions
      run_test test_integrator_ignores_leases_and_artifacts
      run_test test_integrator_ignores_uppercase_legacy_paths
      run_test test_integrator_ignores_claude_state_file
      run_test test_integrator_only_commits_allowed_paths_intersect
      run_test test_integrator_refuses_empty_intersect
      run_test test_integrator_env_prefix_does_not_bypass
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac

  printf 'Week2 integrator tests: %s passed, %s failed\n' "$pass_count" "$fail_count"
  [ "$fail_count" -eq 0 ]
}

main "$@"
