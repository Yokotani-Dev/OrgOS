#!/usr/bin/env bash
# Kernel v2 deployment tests
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
DEPLOY=${DEPLOY:-"$REPO_ROOT/scripts/org/deploy-kernel-v2.sh"}

REQUIRED_FILES=(
  ".claude/hooks/pretool_policy.py"
  ".claude/hooks/policy_core.py"
  ".claude/state/kernel-mode.json"
  "scripts/codex/run-in-worktree.sh"
  "scripts/codex/post-exec-audit.sh"
  "scripts/codex/pre-exec-validate.sh"
  "scripts/codex/cleanup-worktrees.sh"
  "scripts/org/set-kernel-mode.sh"
  "scripts/org/integrator-commit.sh"
  "scripts/org/request-integration.sh"
  "scripts/org/acquire-lease.sh"
  "scripts/org/release-lease.sh"
  "scripts/org/list-leases.sh"
  "scripts/org/collect-artifacts.sh"
  "scripts/org/verify-artifact-manifest.py"
  "scripts/org/validate-tasks-yaml.py"
  "scripts/org/update-task.py"
  ".claude/schemas/artifact-manifest.v1.json"
  ".claude/schemas/integration-queue.v1.json"
  ".claude/schemas/lease.v1.json"
  ".claude/evals/KERNEL_FILES"
  ".ai/queue/integration/.gitkeep"
  ".ai/leases.gitkeep"
  ".ai/BOOTSTRAP-OVERRIDES.md"
  ".orgos-kernel-version"
)

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

assert_file_equals() {
  local path="$1"
  local expected="$2"
  local msg="$3"
  local actual
  actual=$(cat "$path")
  [ "$actual" = "$expected" ] || fail "$msg: expected '$expected', got '$actual'"
}

setup_git_repo() {
  local tmp_dir repo
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-deploy-kernel-v2.XXXXXX")
  repo="$tmp_dir/repo"
  mkdir -p "$repo"
  git -C "$repo" init --quiet --initial-branch=main
  printf '%s\n%s\n' "$tmp_dir" "$repo"
}

assert_required_files_exist() {
  local repo="$1"
  local rel
  for rel in "${REQUIRED_FILES[@]}"; do
    assert_exists "$repo/$rel" "deploy should install required kernel file"
  done
}

test_dry_run_lists_files() {
  local fixture tmp_dir repo output_path
  fixture=$(setup_git_repo)
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  output_path="$tmp_dir/dry-run.out"

  "$DEPLOY" "$repo" --dry-run >"$output_path"

  assert_contains "$output_path" "DRY RUN" "dry-run should announce plan"
  assert_contains "$output_path" ".claude/hooks/pretool_policy.py" "dry-run should list payload files"
  assert_contains "$output_path" ".claude/state/kernel-mode.json" "dry-run should list generated mode file"
  assert_not_exists "$repo/.claude/hooks/pretool_policy.py" "dry-run should not copy files"
  assert_not_exists "$repo/.orgos-kernel-version" "dry-run should not write version"
  rm -rf "$tmp_dir"
}

test_deploy_to_empty_repo() {
  local fixture tmp_dir repo
  fixture=$(setup_git_repo)
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')

  "$DEPLOY" "$repo" >/dev/null

  assert_required_files_exist "$repo"
  [ -x "$repo/scripts/codex/run-in-worktree.sh" ] || fail "run-in-worktree.sh should remain executable"
  [ -x "$repo/scripts/org/integrator-commit.sh" ] || fail "integrator-commit.sh should remain executable"
  rm -rf "$tmp_dir"
}

test_deploy_respects_force_flag() {
  local fixture tmp_dir repo stderr_path status
  fixture=$(setup_git_repo)
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  stderr_path="$tmp_dir/stderr.log"
  mkdir -p "$repo/.claude/hooks"
  printf 'local file\n' >"$repo/.claude/hooks/pretool_policy.py"

  set +e
  "$DEPLOY" "$repo" >/dev/null 2>"$stderr_path"
  status=$?
  set -e

  [ "$status" -eq 3 ] || fail "deploy without --force should exit 3 on conflict, got $status"
  assert_contains "$stderr_path" ".claude/hooks/pretool_policy.py" "conflict output should name existing file"
  assert_file_equals "$repo/.claude/hooks/pretool_policy.py" "local file" "deploy without --force should not overwrite"

  "$DEPLOY" "$repo" --force >/dev/null
  cmp "$REPO_ROOT/.claude/hooks/pretool_policy.py" "$repo/.claude/hooks/pretool_policy.py" >/dev/null \
    || fail "deploy with --force should overwrite from source"
  rm -rf "$tmp_dir"
}

test_deploy_writes_kernel_version() {
  local fixture tmp_dir repo
  fixture=$(setup_git_repo)
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')

  "$DEPLOY" "$repo" >/dev/null

  assert_file_equals "$repo/.orgos-kernel-version" "v0.2.0" "deploy should pin kernel version"
  rm -rf "$tmp_dir"
}

test_deploy_writes_protected_only_mode() {
  local fixture tmp_dir repo mode_file
  fixture=$(setup_git_repo)
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  mode_file="$repo/.claude/state/kernel-mode.json"

  "$DEPLOY" "$repo" >/dev/null

  python3 - "$mode_file" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)

assert data["schema_version"] == "orgos.kernel-mode.v2"
assert data["default"] == "warn"
assert data["invariants"]["IntegratorOnlyCommit"] == "enforce"
assert data["invariants"]["ProtectedBranchNoTouch"] == "enforce"
assert data["invariants"]["PerTaskWorktree"] == "warn"
assert data["invariants"]["LeaseBeforeWrite"] == "warn"
assert data["invariants"]["OwnerApprovalForIrreversibleOps"] == "disabled"
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
      run_test test_dry_run_lists_files
      run_test test_deploy_to_empty_repo
      run_test test_deploy_respects_force_flag
      run_test test_deploy_writes_kernel_version
      run_test test_deploy_writes_protected_only_mode
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac

  printf 'Kernel deploy tests: %s passed, %s failed\n' "$pass_count" "$fail_count"
  [ "$fail_count" -eq 0 ]
}

main "$@"
