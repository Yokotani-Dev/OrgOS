#!/usr/bin/env bash
# Day 2 constitutional invariant and KRT regression tests
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
POLICY=${POLICY:-"$REPO_ROOT/.claude/hooks/pretool_policy.py"}
WRAPPER=${WRAPPER:-"$REPO_ROOT/scripts/codex/run-in-worktree.sh"}
COLLECTOR=${COLLECTOR:-"$REPO_ROOT/scripts/org/collect-artifacts.sh"}
VERIFIER=${VERIFIER:-"$REPO_ROOT/scripts/org/verify-artifact-manifest.py"}

pass_count=0
fail_count=0
skip_count=0
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

write_fixture() {
  local fixture_path="$1"
  local actor="$2"
  local tool="$3"
  local command="$4"
  local path="${5:-}"
  local cwd="${6:-/tmp/test-repo}"

  python3 - "$fixture_path" "$actor" "$tool" "$command" "$path" "$cwd" <<'PY'
import json
import sys

fixture_path, actor, tool, command, path, cwd = sys.argv[1:7]
with open(fixture_path, "w", encoding="utf-8") as handle:
    json.dump(
        {
            "tool": tool,
            "command": command,
            "path": path,
            "cwd": cwd,
            "expected_actor": actor,
        },
        handle,
        indent=2,
        sort_keys=True,
    )
    handle.write("\n")
PY
}

expect_policy_denied() {
  local actor="$1"
  local tool="$2"
  local command="$3"
  local path="$4"
  local invariant="$5"
  local tmp_dir fixture stderr_path status

  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-day2-policy.XXXXXX")
  fixture="$tmp_dir/fixture.json"
  stderr_path="$tmp_dir/stderr.log"
  write_fixture "$fixture" "$actor" "$tool" "$command" "$path" "$tmp_dir/repo"

  set +e
  ORGOS_KERNEL_MODE_OVERRIDE=enforce python3 "$POLICY" --test-fixture "$fixture" 2>"$stderr_path"
  status=$?
  set -e

  [ "$status" -eq 2 ] || fail "expected exit 2, got $status"
  assert_contains "$stderr_path" "ORGOS_POLICY_DENY" "policy should deny"
  assert_contains "$stderr_path" "$invariant" "policy should report invariant"
  rm -rf "$tmp_dir"
}

setup_wrapper_fixture() {
  local task_id="$1"
  local tmp_dir repo mock_codex

  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-day2-wrapper.XXXXXX")
  repo="$tmp_dir/repo"
  mock_codex="$tmp_dir/mock-codex"

  git clone --quiet "$REPO_ROOT" "$repo"
  mkdir -p "$repo/scripts/codex" "$repo/scripts/org" "$repo/.ai/CODEX/ORDERS"
  cp "$WRAPPER" "$repo/scripts/codex/run-in-worktree.sh"
  cp "$COLLECTOR" "$repo/scripts/org/collect-artifacts.sh"
  cp "$VERIFIER" "$repo/scripts/org/verify-artifact-manifest.py"
  chmod +x "$repo/scripts/codex/run-in-worktree.sh" "$repo/scripts/org/collect-artifacts.sh" "$repo/scripts/org/verify-artifact-manifest.py"

  cat > "$repo/scripts/codex/pre-exec-validate.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "$repo/scripts/codex/pre-exec-validate.sh"

  cat > "$repo/scripts/codex/post-exec-audit.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "$repo/scripts/codex/post-exec-audit.sh"

  printf '# test order for %s\n' "$task_id" > "$repo/.ai/CODEX/ORDERS/$task_id.md"
  printf '%s\n%s\n%s\n' "$tmp_dir" "$repo" "$mock_codex"
}

write_mock_codex_artifact() {
  local mock_codex="$1"
  cat > "$mock_codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output_last_message=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output-last-message)
      output_last_message=$2
      shift
      ;;
  esac
  shift
done
cat >/dev/null
mkdir -p .ai/REVIEW/T-KRT-004
cat > .ai/REVIEW/T-KRT-004/codex-response.md <<'MARKDOWN'
# Mock Codex response
This file must survive cleanup.
MARKDOWN
printf 'mock stdout\n'
printf 'mock stderr\n' >&2
if [ -n "$output_last_message" ]; then
  mkdir -p "$(dirname "$output_last_message")"
  printf 'mock final message\n' > "$output_last_message"
fi
exit 0
EOF
  chmod +x "$mock_codex"
}

write_mock_codex_noop() {
  local mock_codex="$1"
  cat > "$mock_codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output_last_message=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output-last-message)
      output_last_message=$2
      shift
      ;;
  esac
  shift
done
cat >/dev/null
if [ -n "$output_last_message" ]; then
  mkdir -p "$(dirname "$output_last_message")"
  printf 'mock final message\n' > "$output_last_message"
fi
exit 0
EOF
  chmod +x "$mock_codex"
}

test_krt_001_codex_commit_denied() {
  expect_policy_denied codex Bash "git commit -m test" "" IntegratorOnlyCommit
}

test_krt_002_no_verify_denied() {
  expect_policy_denied codex Bash "git commit --no-verify -m test" "" IntegratorOnlyCommit
}

test_krt_003_codex_checkout_main_denied() {
  expect_policy_denied codex Bash "git checkout main" "" ProtectedBranchNoTouch
}

test_krt_004_artifact_survives() {
  local task_id="T-KRT-004"
  local fixture tmp_dir repo mock_codex stdout_path stderr_path worktree_path artifact_root run_dir manifest_path response_path

  fixture=$(setup_wrapper_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  mock_codex=$(printf '%s\n' "$fixture" | sed -n '3p')
  stdout_path="$tmp_dir/stdout.log"
  stderr_path="$tmp_dir/stderr.log"
  worktree_path="$repo/.worktrees/$task_id"
  artifact_root="$repo/.ai/artifacts/$task_id"
  write_mock_codex_artifact "$mock_codex"

  (
    cd "$repo"
    bash scripts/codex/run-in-worktree.sh "$task_id" --mock-codex "$mock_codex" --cleanup-after-manifest
  ) >"$stdout_path" 2>"$stderr_path"

  assert_not_exists "$worktree_path" "KRT-004 worktree should be removed after manifest verification"
  assert_exists "$artifact_root" "KRT-004 artifact root should exist"
  run_dir=$(find "$artifact_root" -mindepth 1 -maxdepth 1 -type d | head -n 1)
  manifest_path="$run_dir/artifact_manifest.json"
  response_path="$run_dir/files/generated/.ai/REVIEW/T-KRT-004/codex-response.md"
  assert_exists "$manifest_path" "KRT-004 manifest should exist"
  "$VERIFIER" "$manifest_path"
  assert_exists "$response_path" "KRT-004 generated response should be copied"
  assert_contains "$response_path" "This file must survive cleanup." "KRT-004 response content should survive"
  rm -rf "$tmp_dir"
}

test_krt_005_manager_commit_denied() {
  expect_policy_denied manager Bash "git commit -m manager" "" IntegratorOnlyCommit
}

test_krt_006_manager_edit_events_denied() {
  expect_policy_denied manager Edit "" ".ai/EVENTS.jsonl" StateMutationViaOrgTool
}

test_krt_007_integrator_commit_success() {
  bash "$SCRIPT_DIR/test-week2-integrator.sh" --only test_integrator_commit_success
}

test_krt_008_lease_conflict() {
  bash "$SCRIPT_DIR/test-week3-lease.sh" --only test_krt_008_lease_conflict
}

test_krt_009_no_manifest_quarantine() {
  local task_id="T-KRT-009"
  local fixture tmp_dir repo mock_codex stdout_path stderr_path manifest_path worktree_path

  fixture=$(setup_wrapper_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  mock_codex=$(printf '%s\n' "$fixture" | sed -n '3p')
  stdout_path="$tmp_dir/stdout.log"
  stderr_path="$tmp_dir/stderr.log"
  manifest_path="$tmp_dir/missing-manifest.json"
  worktree_path="$repo/.worktrees/$task_id"
  write_mock_codex_noop "$mock_codex"

  (
    cd "$repo"
    bash scripts/codex/run-in-worktree.sh "$task_id" --mock-codex "$mock_codex" \
      --cleanup-after-manifest --artifact-manifest "$manifest_path"
  ) >"$stdout_path" 2>"$stderr_path"

  assert_exists "$worktree_path" "KRT-009 worktree should remain when manifest gate is missing"
  assert_exists "$worktree_path/.orgos-quarantine" "KRT-009 worktree should be quarantined"
  assert_contains "$stderr_path" "ORGOS_CLEANUP_BLOCKED" "KRT-009 should notify cleanup blocked"
  rm -rf "$tmp_dir"
}

test_krt_010_manager_worktree_remove_denied() {
  expect_policy_denied manager Bash "git worktree remove --force /tmp/worktree" "" PerTaskWorktree
}

test_krt_011_env_prefix_bypass_denied() {
  expect_policy_denied codex Bash "ORGOS_INTEGRATOR=1 git commit -m bypass" "" IntegratorOnlyCommit
  expect_policy_denied codex Bash "echo \"ORGOS_INTEGRATOR=1\"; git commit -m sneaky" "" IntegratorOnlyCommit
}

test_krt_012_commit_msg_bypass_denied() {
  expect_policy_denied codex Bash "git commit -m 'add ORGOS_INTEGRATOR=1 docs'" "" IntegratorOnlyCommit
}

run_test() {
  local name="$1"
  current_test_failed=0
  set +e
  "$name"
  local status=$?
  set -e

  if [ "$status" -eq 77 ]; then
    skip_count=$((skip_count + 1))
    printf 'skip - %s\n' "$name"
  elif [ "$status" -eq 0 ] && [ "$current_test_failed" -eq 0 ]; then
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
      run_test test_krt_001_codex_commit_denied
      run_test test_krt_002_no_verify_denied
      run_test test_krt_003_codex_checkout_main_denied
      run_test test_krt_004_artifact_survives
      run_test test_krt_005_manager_commit_denied
      run_test test_krt_006_manager_edit_events_denied
      run_test test_krt_007_integrator_commit_success
      run_test test_krt_008_lease_conflict
      run_test test_krt_009_no_manifest_quarantine
      run_test test_krt_010_manager_worktree_remove_denied
      run_test test_krt_011_env_prefix_bypass_denied
      run_test test_krt_012_commit_msg_bypass_denied
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac

  printf 'KRT day2 tests: %s passed, %s failed, %s skipped\n' "$pass_count" "$fail_count" "$skip_count"
  [ "$fail_count" -eq 0 ]
}

main "$@"
