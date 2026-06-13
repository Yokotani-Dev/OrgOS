#!/usr/bin/env bash
# Integrator plan contract gate tests
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
REQUEST=${REQUEST:-"$REPO_ROOT/scripts/org/request-integration.sh"}
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

assert_contains() {
  local path="$1"
  local needle="$2"
  local msg="$3"
  grep -Fq "$needle" "$path" || fail "$msg: expected '$needle' in $path"
}

assert_failed_item_and_event() {
  local repo="$1"
  local task_id="$2"
  [ "$(find "$repo/.ai/_machine/queue/integration/failed" -name "$task_id.*.json" | wc -l | tr -d ' ')" -eq 1 ] || fail "failed queue item should be recorded for $task_id"
  assert_contains "$repo/.ai/_machine/queue/integration/events.jsonl" "IntegrationFailed" "failure should emit IntegrationFailed"
}

write_plan_schema() {
  local path="$1"
  cat > "$path" <<'JSON'
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "orgos.plan_contract.v1",
  "type": "object",
  "additionalProperties": false,
  "required": ["schema_version", "task_id", "allowed_paths"],
  "properties": {
    "schema_version": { "const": "orgos.plan_contract.v1" },
    "task_id": { "type": "string", "pattern": "^T-[A-Z0-9]+-[A-Z0-9-]+$" },
    "allowed_paths": {
      "type": "array",
      "minItems": 1,
      "items": { "type": "string", "minLength": 1 }
    }
  }
}
JSON
}

setup_repo_fixture() {
  local task_id="$1"
  local tmp_dir repo worktree branch
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-integrator-plan.XXXXXX")
  repo="$tmp_dir/repo"
  worktree="$repo/.worktrees/$task_id"
  branch="task/$task_id-fixture"

  mkdir -p "$repo/scripts/org" "$repo/.claude/schemas" "$repo/.ai/_machine/queue/integration" "$repo/.ai/_machine/plans"
  git -C "$repo" init --quiet --initial-branch=main
  git -C "$repo" config user.name "Test User"
  git -C "$repo" config user.email "test@example.invalid"
  cp "$REQUEST" "$repo/scripts/org/request-integration.sh"
  cp "$INTEGRATOR" "$repo/scripts/org/integrator-commit.sh"
  cp "$VERIFIER" "$repo/scripts/org/verify-artifact-manifest.py"
  write_plan_schema "$repo/.claude/schemas/plan-contract.v1.json"
  chmod +x "$repo/scripts/org/request-integration.sh" "$repo/scripts/org/integrator-commit.sh" "$repo/scripts/org/verify-artifact-manifest.py"

  printf 'base\n' > "$repo/README.md"
  printf 'base outside\n' > "$repo/outside.txt"
  git -C "$repo" add README.md outside.txt scripts/org/request-integration.sh scripts/org/integrator-commit.sh scripts/org/verify-artifact-manifest.py .claude/schemas/plan-contract.v1.json
  git -C "$repo" commit --quiet -m "initial"
  git -C "$repo" worktree add --quiet -b "$branch" "$worktree" main

  printf '%s\n%s\n%s\n%s\n' "$tmp_dir" "$repo" "$worktree" "$branch"
}

write_manifest() {
  local repo="$1"
  local task_id="$2"
  local manifest_dir="$repo/.ai/_machine/artifacts/$task_id/20260515T000000Z-$task_id-plan"
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
    "run_id": f"20260515T000000Z-{task_id}-plan",
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

write_plan() {
  local repo="$1"
  local task_id="$2"
  shift 2
  local plan_path="$repo/.ai/_machine/plans/$task_id.plan.yaml"
  {
    printf 'schema_version: orgos.plan_contract.v1\n'
    printf 'task_id: %s\n' "$task_id"
    printf 'allowed_paths:\n'
    local path
    for path in "$@"; do
      printf '  - "%s"\n' "$path"
    done
  } > "$plan_path"
}

request_queue_item() {
  local repo="$1"
  local task_id="$2"
  local worktree="$3"
  local branch="$4"
  local manifest="$5"
  local allowed_paths="$6"

  "$repo/scripts/org/request-integration.sh" \
    --task-id "$task_id" \
    --worktree-path "$worktree" \
    --branch "$branch" \
    --base-branch main \
    --artifact-manifest "$manifest" \
    --commit-message "test: integrate $task_id" \
    --allowed-paths "$allowed_paths"
}

test_integrator_commits_when_plan_valid_and_changes_match() {
  local task_id="T-PLAN-1"
  local fixture tmp_dir repo worktree branch manifest output
  fixture=$(setup_repo_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  worktree=$(printf '%s\n' "$fixture" | sed -n '3p')
  branch=$(printf '%s\n' "$fixture" | sed -n '4p')
  manifest=$(write_manifest "$repo" "$task_id")
  write_plan "$repo" "$task_id" "README.md"
  printf 'allowed change\n' > "$worktree/README.md"
  request_queue_item "$repo" "$task_id" "$worktree" "$branch" "$manifest" "README.md" >/dev/null

  output=$("$repo/scripts/org/integrator-commit.sh" --task-id "$task_id")

  printf '%s\n' "$output" | grep -Eq '^[0-9a-f]{40}$' || fail "integrator should print commit sha"
  git -C "$worktree" show --name-only --pretty=format: HEAD | grep -Fxq "README.md" || fail "README.md should be committed"
  rm -rf "$tmp_dir"
}

test_integrator_rejects_when_plan_missing() {
  local task_id="T-PLAN-2"
  local fixture tmp_dir repo worktree branch manifest stderr_path status
  fixture=$(setup_repo_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  worktree=$(printf '%s\n' "$fixture" | sed -n '3p')
  branch=$(printf '%s\n' "$fixture" | sed -n '4p')
  manifest=$(write_manifest "$repo" "$task_id")
  stderr_path="$tmp_dir/missing-plan.stderr"
  printf 'allowed change\n' > "$worktree/README.md"
  request_queue_item "$repo" "$task_id" "$worktree" "$branch" "$manifest" "README.md" >/dev/null

  set +e
  "$repo/scripts/org/integrator-commit.sh" --task-id "$task_id" >/dev/null 2>"$stderr_path"
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "integrator should reject missing plan"
  assert_contains "$stderr_path" "plan contract missing" "missing plan should explain refusal"
  assert_failed_item_and_event "$repo" "$task_id"
  rm -rf "$tmp_dir"
}

test_integrator_rejects_changed_file_outside_plan_allowed_paths() {
  local task_id="T-PLAN-3"
  local fixture tmp_dir repo worktree branch manifest stderr_path status
  fixture=$(setup_repo_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  worktree=$(printf '%s\n' "$fixture" | sed -n '3p')
  branch=$(printf '%s\n' "$fixture" | sed -n '4p')
  manifest=$(write_manifest "$repo" "$task_id")
  stderr_path="$tmp_dir/outside-plan.stderr"
  write_plan "$repo" "$task_id" "README.md"
  printf 'allowed change\n' > "$worktree/README.md"
  printf 'outside change\n' > "$worktree/outside.txt"
  request_queue_item "$repo" "$task_id" "$worktree" "$branch" "$manifest" "README.md,outside.txt" >/dev/null

  set +e
  "$repo/scripts/org/integrator-commit.sh" --task-id "$task_id" >/dev/null 2>"$stderr_path"
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "integrator should reject outside plan allowed_paths"
  assert_contains "$stderr_path" "changed file outside plan allowed_paths: outside.txt" "outside plan path should explain refusal"
  assert_failed_item_and_event "$repo" "$task_id"
  rm -rf "$tmp_dir"
}

test_integrator_rejects_when_plan_invalid_schema() {
  local task_id="T-PLAN-4"
  local fixture tmp_dir repo worktree branch manifest stderr_path status
  fixture=$(setup_repo_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  worktree=$(printf '%s\n' "$fixture" | sed -n '3p')
  branch=$(printf '%s\n' "$fixture" | sed -n '4p')
  manifest=$(write_manifest "$repo" "$task_id")
  stderr_path="$tmp_dir/invalid-plan.stderr"
  {
    printf 'schema_version: orgos.plan_contract.v1\n'
    printf 'task_id: %s\n' "$task_id"
  } > "$repo/.ai/_machine/plans/$task_id.plan.yaml"
  printf 'allowed change\n' > "$worktree/README.md"
  request_queue_item "$repo" "$task_id" "$worktree" "$branch" "$manifest" "README.md" >/dev/null

  set +e
  "$repo/scripts/org/integrator-commit.sh" --task-id "$task_id" >/dev/null 2>"$stderr_path"
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "integrator should reject schema-invalid plan"
  assert_contains "$stderr_path" "plan contract failed schema validation" "invalid plan should explain schema refusal"
  assert_failed_item_and_event "$repo" "$task_id"
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
      run_test test_integrator_commits_when_plan_valid_and_changes_match
      run_test test_integrator_rejects_when_plan_missing
      run_test test_integrator_rejects_changed_file_outside_plan_allowed_paths
      run_test test_integrator_rejects_when_plan_invalid_schema
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac

  printf 'Integrator plan contract tests: %s passed, %s failed\n' "$pass_count" "$fail_count"
  [ "$fail_count" -eq 0 ]
}

main "$@"
