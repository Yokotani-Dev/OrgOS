#!/usr/bin/env bash
# T-OS-492: integrator-flow defect fixes
#   (a) sanctioned main integration (--allow-main + CONTROL allow_main_mutation)
#   (b) collect-artifacts excludes the artifact store (no snapshots-of-snapshots)
#   (c) configurable diff-line cap (default 20000, --max-diff-lines / ORGOS_MAX_DIFF_LINES)
#   (d) plan-contract validation scoped to the task's selected paths, not the whole tree
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
REQUEST=${REQUEST:-"$REPO_ROOT/scripts/org/request-integration.sh"}
INTEGRATOR=${INTEGRATOR:-"$REPO_ROOT/scripts/org/integrator-commit.sh"}
VERIFIER=${VERIFIER:-"$REPO_ROOT/scripts/org/verify-artifact-manifest.py"}
COLLECT=${COLLECT:-"$REPO_ROOT/scripts/org/collect-artifacts.sh"}

pass_count=0
fail_count=0
current_test_failed=0

fail() {
  printf 'not ok - %s\n' "$1" >&2
  current_test_failed=1
  return 1
}

assert_exists() {
  [ -e "$1" ] || fail "$2: missing $1"
}

assert_contains() {
  grep -Fq "$2" "$1" || fail "$3: expected '$2' in $1"
}

write_control() {
  # $1=repo  $2=allow_main_mutation value (true|false)
  mkdir -p "$1/.ai"
  cat > "$1/.ai/CONTROL.yaml" <<EOF
project_name: "kernel-test"
stage: INTEGRATION
allow_main_mutation: $2
main_branch: "main"
EOF
}

write_plan_schema() {
  cat > "$1" <<'JSON'
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

# Build a repo with a task-branch worktree (default integrator fixture).
setup_repo_fixture() {
  local task_id="$1"
  local allow_main="${2:-true}"
  local tmp_dir repo worktree branch
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-integ-fix.XXXXXX")
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
  write_control "$repo" "$allow_main"
  chmod +x "$repo/scripts/org/request-integration.sh" "$repo/scripts/org/integrator-commit.sh" "$repo/scripts/org/verify-artifact-manifest.py"

  printf 'base readme\n' > "$repo/README.md"
  printf 'base outside\n' > "$repo/outside.txt"
  git -C "$repo" add README.md outside.txt scripts/org/request-integration.sh scripts/org/integrator-commit.sh scripts/org/verify-artifact-manifest.py .claude/schemas/plan-contract.v1.json
  git -C "$repo" commit --quiet -m "initial"
  git -C "$repo" worktree add --quiet -b "$branch" "$worktree" main

  printf '%s\n%s\n%s\n%s\n' "$tmp_dir" "$repo" "$worktree" "$branch"
}

write_plan() {
  # $1=repo  $2=task_id  $3..=allowed paths
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

write_manifest() {
  local repo="$1"
  local task_id="$2"
  local manifest_dir="$repo/.ai/_machine/artifacts/$task_id/20260612T000000Z-$task_id-fix"
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
content = (manifest_dir / "logs" / "stdout.log").read_bytes()
payload = {
    "schema_version": "orgos.artifact_manifest.v1",
    "project_id": "orgos-test",
    "task_id": task_id,
    "run_id": f"20260612T000000Z-{task_id}-fix",
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

# ---------------------------------------------------------------------------
# (a) Sanctioned main integration
# ---------------------------------------------------------------------------

test_main_integration_succeeds_when_allowed() {
  local task_id="T-MAIN-1"
  local fixture tmp_dir repo manifest output head_msg main_worktree
  fixture=$(setup_repo_fixture "$task_id" "true")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  manifest=$(write_manifest "$repo" "$task_id")

  # main-targeted integration: the worktree branch IS main.
  main_worktree="$repo"
  printf 'integrated on main\n' > "$main_worktree/README.md"
  write_plan "$repo" "$task_id" "README.md"

  "$repo/scripts/org/request-integration.sh" \
    --task-id "$task_id" \
    --worktree-path "$main_worktree" \
    --branch main \
    --base-branch main \
    --artifact-manifest "$manifest" \
    --commit-message "feat: main integration $task_id" \
    --allowed-paths "README.md" \
    --allow-main >/dev/null

  output=$("$repo/scripts/org/integrator-commit.sh" --task-id "$task_id")
  head_msg=$(git -C "$main_worktree" log -1 --pretty=%s)

  printf '%s\n' "$output" | grep -Eq '^[0-9a-f]{40}$' || fail "main integration should print commit sha"
  [ "$head_msg" = "feat: main integration $task_id" ] || fail "main integration should land commit on main"
  [ "$(git -C "$main_worktree" branch --show-current)" = "main" ] || fail "commit should be on main branch"
  [ "$(find "$repo/.ai/_machine/queue/integration/done" -name "$task_id.*.json" | wc -l | tr -d ' ')" -eq 1 ] || fail "queue item should be done"
  rm -rf "$tmp_dir"
}

test_main_integration_blocked_when_disallowed() {
  local task_id="T-MAIN-2"
  local fixture tmp_dir repo manifest stderr_path status
  fixture=$(setup_repo_fixture "$task_id" "false")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  manifest=$(write_manifest "$repo" "$task_id")
  stderr_path="$tmp_dir/main-disallowed.stderr"
  printf 'attempt on main\n' > "$repo/README.md"

  set +e
  "$repo/scripts/org/request-integration.sh" \
    --task-id "$task_id" \
    --worktree-path "$repo" \
    --branch main \
    --base-branch main \
    --artifact-manifest "$manifest" \
    --commit-message "feat: blocked main $task_id" \
    --allowed-paths "README.md" \
    --allow-main >/dev/null 2>"$stderr_path"
  status=$?
  set -e

  [ "$status" -eq 2 ] || fail "main integration must be blocked when allow_main_mutation=false (got $status)"
  assert_contains "$stderr_path" "allow_main_mutation must be true" "block should explain CONTROL gate"
  rm -rf "$tmp_dir"
}

test_main_integration_blocked_without_allow_main_flag() {
  local task_id="T-MAIN-3"
  local fixture tmp_dir repo manifest stderr_path status
  fixture=$(setup_repo_fixture "$task_id" "true")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  manifest=$(write_manifest "$repo" "$task_id")
  stderr_path="$tmp_dir/main-no-flag.stderr"
  printf 'attempt on main\n' > "$repo/README.md"

  set +e
  "$repo/scripts/org/request-integration.sh" \
    --task-id "$task_id" \
    --worktree-path "$repo" \
    --branch main \
    --base-branch main \
    --artifact-manifest "$manifest" \
    --commit-message "feat: no flag $task_id" \
    --allowed-paths "README.md" >/dev/null 2>"$stderr_path"
  status=$?
  set -e

  [ "$status" -eq 2 ] || fail "branch main without --allow-main must still be rejected (got $status)"
  assert_contains "$stderr_path" "protected branch is not a task branch" "default still ProtectedBranchNoTouch"
  rm -rf "$tmp_dir"
}

test_develop_still_blocked_with_allow_main() {
  local task_id="T-MAIN-4"
  local fixture tmp_dir repo manifest stderr_path status
  fixture=$(setup_repo_fixture "$task_id" "true")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  manifest=$(write_manifest "$repo" "$task_id")
  stderr_path="$tmp_dir/develop-blocked.stderr"
  printf 'attempt on develop\n' > "$repo/README.md"

  set +e
  "$repo/scripts/org/request-integration.sh" \
    --task-id "$task_id" \
    --worktree-path "$repo" \
    --branch develop \
    --base-branch develop \
    --artifact-manifest "$manifest" \
    --commit-message "feat: develop $task_id" \
    --allowed-paths "README.md" \
    --allow-main >/dev/null 2>"$stderr_path"
  status=$?
  set -e

  [ "$status" -eq 2 ] || fail "develop must stay blocked even with --allow-main (got $status)"
  assert_contains "$stderr_path" "protected branch is not a task branch: develop" "develop keeps no-touch semantics"
  rm -rf "$tmp_dir"
}

test_integrator_rejects_forged_main_integration_flag() {
  # A queue item that claims main_integration on a branch=main but CONTROL says false
  # must still be rejected at the integrator (defense in depth: re-verify CONTROL).
  local task_id="T-MAIN-5"
  local fixture tmp_dir repo manifest queue_path stderr_path status
  fixture=$(setup_repo_fixture "$task_id" "true")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  manifest=$(write_manifest "$repo" "$task_id")
  stderr_path="$tmp_dir/forged.stderr"
  printf 'integrated on main\n' > "$repo/README.md"

  queue_path=$("$repo/scripts/org/request-integration.sh" \
    --task-id "$task_id" \
    --worktree-path "$repo" \
    --branch main \
    --base-branch main \
    --artifact-manifest "$manifest" \
    --commit-message "feat: forged $task_id" \
    --allowed-paths "README.md" \
    --allow-main)

  # Owner revokes allow_main_mutation between request and integrate.
  write_control "$repo" "false"

  set +e
  "$repo/scripts/org/integrator-commit.sh" --task-id "$task_id" >/dev/null 2>"$stderr_path"
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "integrator must re-verify CONTROL and reject revoked main mutation"
  assert_contains "$stderr_path" "main integration denied" "integrator should re-check allow_main_mutation"
  rm -rf "$tmp_dir"
}

# ---------------------------------------------------------------------------
# (c) Configurable diff cap
# ---------------------------------------------------------------------------

test_diff_cap_default_is_20000() {
  local task_id="T-CAP-1"
  local fixture tmp_dir repo manifest queue_path
  fixture=$(setup_repo_fixture "$task_id" "true")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  manifest=$(write_manifest "$repo" "$task_id")
  printf 'change\n' > "$repo/.worktrees/$task_id/README.md"

  queue_path=$("$repo/scripts/org/request-integration.sh" \
    --task-id "$task_id" \
    --worktree-path "$repo/.worktrees/$task_id" \
    --branch "task/$task_id-fixture" \
    --base-branch main \
    --artifact-manifest "$manifest" \
    --commit-message "test: default cap" \
    --allowed-paths "README.md")

  python3 - "$queue_path" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert data["scope"]["diff_budget"]["max_lines"] == 20000, data["scope"]["diff_budget"]
PY
  [ "$current_test_failed" -eq 0 ] || return 1
  rm -rf "$tmp_dir"
}

test_diff_cap_flag_and_env_override() {
  local task_id="T-CAP-2"
  local fixture tmp_dir repo manifest queue_path
  fixture=$(setup_repo_fixture "$task_id" "true")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  manifest=$(write_manifest "$repo" "$task_id")
  printf 'change\n' > "$repo/.worktrees/$task_id/README.md"

  # --max-diff-lines flag
  queue_path=$("$repo/scripts/org/request-integration.sh" \
    --task-id "$task_id" \
    --worktree-path "$repo/.worktrees/$task_id" \
    --branch "task/$task_id-fixture" \
    --base-branch main \
    --artifact-manifest "$manifest" \
    --commit-message "test: flag cap" \
    --allowed-paths "README.md" \
    --max-diff-lines 50000)
  python3 - "$queue_path" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert data["scope"]["diff_budget"]["max_lines"] == 50000, data["scope"]["diff_budget"]
PY
  [ "$current_test_failed" -eq 0 ] || { rm -rf "$tmp_dir"; return 1; }

  # ORGOS_MAX_DIFF_LINES env (re-request a different task id to avoid pending collision)
  rm -f "$queue_path"
  ORGOS_MAX_DIFF_LINES=33333 queue_path=$(ORGOS_MAX_DIFF_LINES=33333 "$repo/scripts/org/request-integration.sh" \
    --task-id "$task_id" \
    --worktree-path "$repo/.worktrees/$task_id" \
    --branch "task/$task_id-fixture" \
    --base-branch main \
    --artifact-manifest "$manifest" \
    --commit-message "test: env cap" \
    --allowed-paths "README.md")
  python3 - "$queue_path" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert data["scope"]["diff_budget"]["max_lines"] == 33333, data["scope"]["diff_budget"]
PY
  [ "$current_test_failed" -eq 0 ] || return 1
  rm -rf "$tmp_dir"
}

test_large_diff_integrates_under_higher_cap() {
  # A >5000-line change that would have been blocked by the old hardcoded cap
  # must now integrate under the default 20000 cap.
  local task_id="T-CAP-3"
  local fixture tmp_dir repo worktree branch manifest output
  fixture=$(setup_repo_fixture "$task_id" "true")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  worktree=$(printf '%s\n' "$fixture" | sed -n '3p')
  branch=$(printf '%s\n' "$fixture" | sed -n '4p')
  manifest=$(write_manifest "$repo" "$task_id")

  # 8000-line file (> old 5000 cap, < new 20000 default).
  python3 - "$worktree/README.md" <<'PY'
import sys
with open(sys.argv[1], "w") as handle:
    handle.write("\n".join(f"line {i}" for i in range(8000)) + "\n")
PY
  write_plan "$repo" "$task_id" "README.md"

  "$repo/scripts/org/request-integration.sh" \
    --task-id "$task_id" \
    --worktree-path "$worktree" \
    --branch "$branch" \
    --base-branch main \
    --artifact-manifest "$manifest" \
    --commit-message "feat: large change $task_id" \
    --allowed-paths "README.md" >/dev/null

  output=$("$repo/scripts/org/integrator-commit.sh" --task-id "$task_id")
  printf '%s\n' "$output" | grep -Eq '^[0-9a-f]{40}$' || fail "large (8000-line) diff should integrate under 20000 cap"
  rm -rf "$tmp_dir"
}

test_diff_cap_still_enforced() {
  # The guard is configurable, NOT removed: a change above the cap is still rejected.
  local task_id="T-CAP-4"
  local fixture tmp_dir repo worktree branch manifest stderr_path status
  fixture=$(setup_repo_fixture "$task_id" "true")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  worktree=$(printf '%s\n' "$fixture" | sed -n '3p')
  branch=$(printf '%s\n' "$fixture" | sed -n '4p')
  manifest=$(write_manifest "$repo" "$task_id")
  stderr_path="$tmp_dir/over-cap.stderr"

  python3 - "$worktree/README.md" <<'PY'
import sys
with open(sys.argv[1], "w") as handle:
    handle.write("\n".join(f"line {i}" for i in range(300)) + "\n")
PY

  "$repo/scripts/org/request-integration.sh" \
    --task-id "$task_id" \
    --worktree-path "$worktree" \
    --branch "$branch" \
    --base-branch main \
    --artifact-manifest "$manifest" \
    --commit-message "feat: over cap $task_id" \
    --allowed-paths "README.md" \
    --max-diff-lines 100 >/dev/null

  set +e
  "$repo/scripts/org/integrator-commit.sh" --task-id "$task_id" >/dev/null 2>"$stderr_path"
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "diff over the (configured) cap must still be rejected"
  assert_contains "$stderr_path" "diff budget exceeded" "cap guard message"
  rm -rf "$tmp_dir"
}

# ---------------------------------------------------------------------------
# (d) Plan contract scoped to task paths, not the whole worktree
# ---------------------------------------------------------------------------

test_plan_contract_ignores_unrelated_dirty_tree() {
  # A shared worktree carries an unrelated dirty file outside the plan's allowed_paths.
  # The plan contract must validate only the SELECTED change set, so integration succeeds.
  local task_id="T-PLAN-SCOPE-1"
  local fixture tmp_dir repo worktree branch manifest plan_path output changed
  fixture=$(setup_repo_fixture "$task_id" "true")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  worktree=$(printf '%s\n' "$fixture" | sed -n '3p')
  branch=$(printf '%s\n' "$fixture" | sed -n '4p')
  manifest=$(write_manifest "$repo" "$task_id")

  plan_path="$repo/.ai/_machine/plans/$task_id.plan.yaml"
  {
    printf 'schema_version: orgos.plan_contract.v1\n'
    printf 'task_id: %s\n' "$task_id"
    printf 'allowed_paths:\n'
    printf '  - "README.md"\n'
  } > "$plan_path"

  printf 'task change\n' > "$worktree/README.md"
  # Unrelated dirty file (shared tree) outside both the task scope and the plan.
  printf 'unrelated dirty change\n' > "$worktree/outside.txt"

  # Request scope only declares README.md (the task's path); outside.txt is left dirty.
  "$repo/scripts/org/request-integration.sh" \
    --task-id "$task_id" \
    --worktree-path "$worktree" \
    --branch "$branch" \
    --base-branch main \
    --artifact-manifest "$manifest" \
    --commit-message "feat: partitioned $task_id" \
    --allowed-paths "README.md" >/dev/null

  output=$("$repo/scripts/org/integrator-commit.sh" --task-id "$task_id")
  printf '%s\n' "$output" | grep -Eq '^[0-9a-f]{40}$' || fail "partitioned integration should succeed despite unrelated dirty file"

  changed=$(git -C "$worktree" show --name-only --pretty=format: HEAD)
  printf '%s\n' "$changed" | grep -Fxq "README.md" || fail "README.md should be committed"
  ! printf '%s\n' "$changed" | grep -Fxq "outside.txt" || fail "unrelated outside.txt must NOT be committed"
  git -C "$worktree" status --porcelain | grep -Fq "outside.txt" || fail "outside.txt should remain dirty/untracked"
  rm -rf "$tmp_dir"
}

test_plan_contract_still_rejects_in_scope_violation() {
  # The plan gate is scoped, NOT disabled: if a SELECTED (declared) path is outside the
  # plan's allowed_paths, it must still be rejected.
  local task_id="T-PLAN-SCOPE-2"
  local fixture tmp_dir repo worktree branch manifest plan_path stderr_path status
  fixture=$(setup_repo_fixture "$task_id" "true")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  worktree=$(printf '%s\n' "$fixture" | sed -n '3p')
  branch=$(printf '%s\n' "$fixture" | sed -n '4p')
  manifest=$(write_manifest "$repo" "$task_id")
  stderr_path="$tmp_dir/plan-violation.stderr"

  plan_path="$repo/.ai/_machine/plans/$task_id.plan.yaml"
  {
    printf 'schema_version: orgos.plan_contract.v1\n'
    printf 'task_id: %s\n' "$task_id"
    printf 'allowed_paths:\n'
    printf '  - "README.md"\n'
  } > "$plan_path"

  printf 'task change\n' > "$worktree/README.md"
  printf 'declared but not in plan\n' > "$worktree/outside.txt"

  # Scope DECLARES outside.txt (so it is selected for commit) but plan does NOT allow it.
  "$repo/scripts/org/request-integration.sh" \
    --task-id "$task_id" \
    --worktree-path "$worktree" \
    --branch "$branch" \
    --base-branch main \
    --artifact-manifest "$manifest" \
    --commit-message "feat: scope violation $task_id" \
    --allowed-paths "README.md,outside.txt" >/dev/null

  set +e
  "$repo/scripts/org/integrator-commit.sh" --task-id "$task_id" >/dev/null 2>"$stderr_path"
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "a selected path outside the plan must still be rejected"
  assert_contains "$stderr_path" "changed file outside plan allowed_paths: outside.txt" "scoped plan gate still fires"
  rm -rf "$tmp_dir"
}

# ---------------------------------------------------------------------------
# (b) collect-artifacts excludes the artifact store (no recursion)
# ---------------------------------------------------------------------------

test_collect_artifacts_excludes_artifact_store() {
  local tmp_dir worktree artifact_dir run_id manifest snapshot_count
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-collect-fix.XXXXXX")
  worktree="$tmp_dir/repo"
  mkdir -p "$worktree"
  git -C "$worktree" init --quiet --initial-branch=main
  git -C "$worktree" config user.name "Test User"
  git -C "$worktree" config user.email "test@example.invalid"
  printf 'base\n' > "$worktree/README.md"
  git -C "$worktree" add README.md
  git -C "$worktree" commit --quiet -m "initial"

  # Pre-existing artifact store from prior runs (the recursion source). Many files,
  # NO .gitignore present -> worst case where git would otherwise list them all.
  mkdir -p "$worktree/.ai/_machine/artifacts/T-OS-OLD/run1/files/untracked/.ai/ARTIFACTS/T-OS-OLDER"
  mkdir -p "$worktree/.ai/ARTIFACTS/T-OS-LEGACY/legacy"
  mkdir -p "$worktree/.ai/_machine/queue/integration/done/202606"
  python3 - "$worktree" <<'PY'
import sys
from pathlib import Path
root = Path(sys.argv[1])
store = root / ".ai/_machine/artifacts/T-OS-OLD/run1/files/untracked/.ai/ARTIFACTS/T-OS-OLDER"
for i in range(600):
    (store / f"snapshot-{i}.json").write_text("{}\n")
(root / ".ai/ARTIFACTS/T-OS-LEGACY/legacy/m.json").write_text("{}\n")
for i in range(50):
    (root / ".ai/_machine/queue/integration/done/202606" / f"item-{i}.json").write_text("{}\n")
PY

  # A real task artifact the agent produced (must still be collected).
  printf 'generated output\n' > "$worktree/result.txt"

  artifact_dir="$worktree/.ai/_machine/artifacts/T-OS-NEW/run-new"
  run_id="20260612T010101Z-T-OS-NEW-abcd1234"
  printf 'out\n' > "$tmp_dir/stdout.log"
  printf 'err\n' > "$tmp_dir/stderr.log"
  printf 'last\n' > "$tmp_dir/last.txt"

  set +e
  ORGOS_APPEND_EVENT="$tmp_dir/noop-append.py" \
  "$COLLECT" \
    --task-id T-OS-NEW \
    --run-id "$run_id" \
    --worktree-path "$worktree" \
    --artifact-dir "$artifact_dir" \
    --stdout-source "$tmp_dir/stdout.log" \
    --stderr-source "$tmp_dir/stderr.log" \
    --last-message-source "$tmp_dir/last.txt" \
    --actor-role tester \
    --actor-id kernel >/dev/null 2>"$tmp_dir/collect.stderr"
  status=$?
  set -e
  [ "$status" -eq 0 ] || { cat "$tmp_dir/collect.stderr" >&2; fail "collect-artifacts should succeed"; rm -rf "$tmp_dir"; return 1; }

  manifest="$artifact_dir/artifact_manifest.json"
  assert_exists "$manifest" "manifest should be written"

  # No artifact-store paths should have been snapshotted into files/.
  # Scope to RELATIVE paths under files/ so the artifact_dir's own absolute path
  # (which itself lives under .ai/_machine/artifacts/) does not cause a false positive.
  if ( cd "$artifact_dir" && find files -type f 2>/dev/null ) \
      | grep -Ei 'artifacts/|_machine/queue/' | grep -q .; then
    fail "artifact store / queue paths must NOT be snapshotted (recursion)"
  fi

  # The legitimate task output must still be collected.
  python3 - "$manifest" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
rels = [a.get("source_relpath", "") for a in m.get("artifacts", [])]
assert any(r == "result.txt" for r in rels), f"result.txt should be collected: {rels}"
assert not any(".ai/_machine/artifacts/" in r.lower() or ".ai/artifacts/" in r.lower() for r in rels), \
    f"artifact store paths leaked into manifest: {rels}"
PY
  [ "$current_test_failed" -eq 0 ] || { rm -rf "$tmp_dir"; return 1; }

  # Bound: collected file tree must stay small (< 2000), proving no explosion.
  snapshot_count=$(find "$artifact_dir/files" -type f 2>/dev/null | wc -l | tr -d ' ')
  [ "$snapshot_count" -lt 2000 ] || fail "collected file count exploded: $snapshot_count >= 2000"

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
    --only) shift; run_test "$1" ;;
    "")
      run_test test_main_integration_succeeds_when_allowed
      run_test test_main_integration_blocked_when_disallowed
      run_test test_main_integration_blocked_without_allow_main_flag
      run_test test_develop_still_blocked_with_allow_main
      run_test test_integrator_rejects_forged_main_integration_flag
      run_test test_diff_cap_default_is_20000
      run_test test_diff_cap_flag_and_env_override
      run_test test_large_diff_integrates_under_higher_cap
      run_test test_diff_cap_still_enforced
      run_test test_plan_contract_ignores_unrelated_dirty_tree
      run_test test_plan_contract_still_rejects_in_scope_violation
      run_test test_collect_artifacts_excludes_artifact_store
      ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac

  printf 'Integrator flow fix tests: %s passed, %s failed\n' "$pass_count" "$fail_count"
  [ "$fail_count" -eq 0 ]
}

main "$@"
