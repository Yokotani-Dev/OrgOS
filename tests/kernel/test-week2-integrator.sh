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
  mkdir -p "$repo/scripts/org" "$repo/.claude/hooks" "$repo/.claude/schemas" "$repo/.ai/queue/integration"
  cp "$REQUEST" "$repo/scripts/org/request-integration.sh"
  cp "$INTEGRATOR" "$repo/scripts/org/integrator-commit.sh"
  cp "$REPO_ROOT/scripts/org/verify-artifact-manifest.py" "$repo/scripts/org/verify-artifact-manifest.py"
  cp "$POLICY" "$repo/.claude/hooks/pretool_policy.py"
  cp "$REPO_ROOT/.claude/hooks/policy_core.py" "$repo/.claude/hooks/policy_core.py"
  cp "$SCHEMA" "$repo/.claude/schemas/integration-queue.v1.json"
  chmod +x "$repo/scripts/org/request-integration.sh" "$repo/scripts/org/integrator-commit.sh" "$repo/scripts/org/verify-artifact-manifest.py"

  printf 'base\n' > "$repo/README.md"
  git -C "$repo" add README.md scripts/org/request-integration.sh scripts/org/integrator-commit.sh scripts/org/verify-artifact-manifest.py .claude/hooks/pretool_policy.py .claude/hooks/policy_core.py .claude/schemas/integration-queue.v1.json
  git -C "$repo" commit --quiet -m "initial"
  git -C "$repo" worktree add --quiet -b "$branch" "$worktree" main

  printf '%s\n%s\n%s\n%s\n' "$tmp_dir" "$repo" "$worktree" "$branch"
}

write_manifest() {
  local repo="$1"
  local task_id="$2"
  local manifest_dir="$repo/.ai/artifacts/$task_id/20260515T000000Z-$task_id-1234abcd"
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
    --commit-message "test: integrate $task_id")

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
    --commit-message "test: reject protected" >/dev/null 2>&1
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "protected branch request should fail"
  rm -rf "$tmp_dir"
}

test_integrator_commit_success() {
  local task_id="T-TEST-3"
  local fixture tmp_dir repo worktree branch manifest queue_path output done_count head_msg
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
    --commit-message "test: integrate $task_id")

  output=$("$repo/scripts/org/integrator-commit.sh" --task-id "$task_id")
  done_count=$(find "$repo/.ai/queue/integration/done" -name "$task_id.*.json" | wc -l | tr -d ' ')
  head_msg=$(git -C "$worktree" log -1 --pretty=%s)

  [ "$done_count" -eq 1 ] || fail "integrator should move queue item to done"
  [ "$head_msg" = "test: integrate $task_id" ] || fail "integrator should create commit"
  assert_not_exists "$queue_path" "pending queue item should be consumed"
  printf '%s\n' "$output" | grep -Eq '^[0-9a-f]{40}$' || fail "integrator should print commit sha"
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
    --commit-message "test: missing manifest")
  rm "$manifest"

  set +e
  "$repo/scripts/org/integrator-commit.sh" --queue-item "$queue_path" --task-id "$task_id" >/dev/null 2>&1
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "integrator should reject missing manifest"
  [ "$(find "$repo/.ai/queue/integration/failed" -name "$task_id.*.json" | wc -l | tr -d ' ')" -eq 1 ] || fail "failed item should be recorded"
  rm -rf "$tmp_dir"
}

test_integrator_commit_blocks_diff_outside_allowed_paths() {
  local task_id="T-TEST-5"
  local fixture tmp_dir repo worktree branch manifest queue_path status
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
    --commit-message "test: scope")
  printf 'outside\n' > "$worktree/outside.txt"

  set +e
  "$repo/scripts/org/integrator-commit.sh" --task-id "$task_id" >/dev/null 2>&1
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "integrator should reject files outside allowed_paths"
  assert_not_exists "$queue_path" "failed queue item should leave pending"
  [ "$(find "$repo/.ai/queue/integration/failed" -name "$task_id.*.json" | wc -l | tr -d ' ')" -eq 1 ] || fail "failed scope item should be recorded"
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
    --commit-message "test: ignore queue state $task_id" >/dev/null
  mkdir -p "$worktree/.ai/queue/integration/processing"
  printf '{"status":"processing"}\n' > "$worktree/.ai/queue/integration/processing/$task_id.json"

  output=$("$repo/scripts/org/integrator-commit.sh" --task-id "$task_id")
  done_count=$(find "$repo/.ai/queue/integration/done" -name "$task_id.*.json" | wc -l | tr -d ' ')

  [ "$done_count" -eq 1 ] || fail "integrator should move queue item to done with queue state present"
  printf '%s\n' "$output" | grep -Eq '^[0-9a-f]{40}$' || fail "integrator should print commit sha"
  ! git -C "$worktree" show --name-only --pretty=format: HEAD | grep -Fq ".ai/queue/integration/" || fail "queue state should not be committed"
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
    --commit-message "test: ignore internal state $task_id" >/dev/null
  mkdir -p "$worktree/.ai/leases" "$worktree/.ai/artifacts/$task_id" "$worktree/.ai/alerts"
  printf '{"holder":"integrator"}\n' > "$worktree/.ai/leases/$task_id.json"
  printf 'runtime artifact\n' > "$worktree/.ai/artifacts/$task_id/runtime.log"
  printf 'alert log\n' > "$worktree/.ai/alerts/$task_id.log"

  output=$("$repo/scripts/org/integrator-commit.sh" --task-id "$task_id")
  done_count=$(find "$repo/.ai/queue/integration/done" -name "$task_id.*.json" | wc -l | tr -d ' ')

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
    --commit-message "test: ignore uppercase legacy paths $task_id" >/dev/null
  mkdir -p "$worktree/.ai/ARTIFACTS/$task_id/legacy" "$worktree/.ai/artifacts/$task_id/runtime"
  printf '{"legacy":true}\n' > "$worktree/.ai/ARTIFACTS/$task_id/legacy/artifact_manifest.json"
  printf 'runtime artifact\n' > "$worktree/.ai/artifacts/$task_id/runtime/output.log"

  output=$("$repo/scripts/org/integrator-commit.sh" --task-id "$task_id")
  done_count=$(find "$repo/.ai/queue/integration/done" -name "$task_id.*.json" | wc -l | tr -d ' ')

  [ "$done_count" -eq 1 ] || fail "integrator should move queue item to done with uppercase legacy artifacts present"
  printf '%s\n' "$output" | grep -Eq '^[0-9a-f]{40}$' || fail "integrator should print commit sha"
  ! git -C "$worktree" show --name-only --pretty=format: HEAD | grep -Eqi '^\.ai/artifacts/' || fail "artifact paths should not be committed regardless of case"
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
    --commit-message "test: ignore claude state $task_id" >/dev/null
  mkdir -p "$worktree/.claude/state"
  printf 'pid=123 task_id=%s\n' "$task_id" > "$worktree/.claude/state/git.lock"

  output=$("$repo/scripts/org/integrator-commit.sh" --task-id "$task_id")
  done_count=$(find "$repo/.ai/queue/integration/done" -name "$task_id.*.json" | wc -l | tr -d ' ')

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
      run_test test_request_integration_rejects_protected_branch
      run_test test_integrator_commit_success
      run_test test_integrator_commit_blocks_without_manifest
      run_test test_integrator_commit_blocks_diff_outside_allowed_paths
      run_test test_integrator_ignores_queue_state_transitions
      run_test test_integrator_ignores_leases_and_artifacts
      run_test test_integrator_ignores_uppercase_legacy_paths
      run_test test_integrator_ignores_claude_state_file
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
