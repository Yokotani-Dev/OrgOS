#!/usr/bin/env bash
# Day 0 cleanup_worktree() fail-closed tests
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
SCRIPT_UNDER_TEST=${SCRIPT_UNDER_TEST:-"$REPO_ROOT/scripts/codex/run-in-worktree.sh"}

pass_count=0
fail_count=0

fail() {
  printf 'not ok - %s\n' "$1" >&2
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

setup_fixture() {
  local task_id="$1"
  local tmp_dir repo codex_stub

  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-day0-cleanup.XXXXXX")
  repo="$tmp_dir/repo"
  codex_stub="$tmp_dir/codex-stub"

  git clone --quiet "$REPO_ROOT" "$repo"

  mkdir -p "$repo/scripts/codex" "$repo/.ai/CODEX/ORDERS"
  cp "$SCRIPT_UNDER_TEST" "$repo/scripts/codex/run-in-worktree.sh"
  chmod +x "$repo/scripts/codex/run-in-worktree.sh"

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

  cat > "$codex_stub" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
exit 0
EOF
  chmod +x "$codex_stub"

  printf '# test order for %s\n' "$task_id" > "$repo/.ai/CODEX/ORDERS/$task_id.md"

  printf '%s\n%s\n%s\n' "$tmp_dir" "$repo" "$codex_stub"
}

run_wrapper() {
  local repo="$1"
  local codex_stub="$2"
  local task_id="$3"
  local stdout_path="$4"
  local stderr_path="$5"
  shift 5

  (
    cd "$repo"
    ORGOS_CODEX_BIN="$codex_stub" bash scripts/codex/run-in-worktree.sh "$task_id" "$@"
  ) >"$stdout_path" 2>"$stderr_path"
}

test_default_preserve() {
  local task_id="T-DAY0-DEFAULT"
  local fixture tmp_dir repo codex_stub stdout_path stderr_path worktree_path
  fixture=$(setup_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  codex_stub=$(printf '%s\n' "$fixture" | sed -n '3p')
  stdout_path="$tmp_dir/stdout.log"
  stderr_path="$tmp_dir/stderr.log"
  worktree_path="$repo/.worktrees/$task_id"

  run_wrapper "$repo" "$codex_stub" "$task_id" "$stdout_path" "$stderr_path"

  assert_exists "$worktree_path" "default run should preserve worktree"
  assert_contains "$stderr_path" "cleanup_status=kept" "default run should log kept status"
  rm -rf "$tmp_dir"
}

test_cleanup_without_manifest_quarantines() {
  local task_id="T-DAY0-NO-MANIFEST"
  local fixture tmp_dir repo codex_stub stdout_path stderr_path worktree_path
  fixture=$(setup_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  codex_stub=$(printf '%s\n' "$fixture" | sed -n '3p')
  stdout_path="$tmp_dir/stdout.log"
  stderr_path="$tmp_dir/stderr.log"
  worktree_path="$repo/.worktrees/$task_id"

  run_wrapper "$repo" "$codex_stub" "$task_id" "$stdout_path" "$stderr_path" --cleanup-after-manifest

  assert_exists "$worktree_path" "cleanup without manifest should preserve worktree"
  assert_exists "$worktree_path/.orgos-quarantine" "cleanup without manifest should quarantine"
  assert_contains "$stderr_path" "ORGOS_CLEANUP_BLOCKED" "cleanup without manifest should notify owner"
  rm -rf "$tmp_dir"
}

test_invalid_manifest_quarantines() {
  local task_id="T-DAY0-BAD-MANIFEST"
  local fixture tmp_dir repo codex_stub stdout_path stderr_path manifest_path worktree_path
  fixture=$(setup_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  codex_stub=$(printf '%s\n' "$fixture" | sed -n '3p')
  stdout_path="$tmp_dir/stdout.log"
  stderr_path="$tmp_dir/stderr.log"
  manifest_path="$tmp_dir/manifest.json"
  worktree_path="$repo/.worktrees/$task_id"
  printf '{ invalid json\n' > "$manifest_path"

  run_wrapper "$repo" "$codex_stub" "$task_id" "$stdout_path" "$stderr_path" \
    --cleanup-after-manifest --artifact-manifest "$manifest_path"

  assert_exists "$worktree_path" "invalid manifest should preserve worktree"
  assert_exists "$worktree_path/.orgos-quarantine" "invalid manifest should quarantine"
  assert_contains "$stderr_path" "ORGOS_CLEANUP_BLOCKED" "invalid manifest should notify owner"
  rm -rf "$tmp_dir"
}

test_valid_manifest_allows_cleanup() {
  local task_id="T-DAY0-VALID-MANIFEST"
  local fixture tmp_dir repo codex_stub stdout_path stderr_path manifest_path worktree_path
  fixture=$(setup_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  codex_stub=$(printf '%s\n' "$fixture" | sed -n '3p')
  stdout_path="$tmp_dir/stdout.log"
  stderr_path="$tmp_dir/stderr.log"
  manifest_path="$tmp_dir/manifest.json"
  worktree_path="$repo/.worktrees/$task_id"
  cat > "$manifest_path" <<EOF
{
  "schema_version": "1.0",
  "task_id": "$task_id",
  "run_id": "run-1",
  "artifacts": []
}
EOF

  run_wrapper "$repo" "$codex_stub" "$task_id" "$stdout_path" "$stderr_path" \
    --cleanup-after-manifest --artifact-manifest "$manifest_path"

  assert_not_exists "$worktree_path" "valid manifest should allow cleanup"
  assert_contains "$stderr_path" "cleanup_status=removed_after_manifest" "valid manifest should log removal status"
  rm -rf "$tmp_dir"
}

test_existing_keep_worktree_compat() {
  local task_id="T-DAY0-KEEP-COMPAT"
  local fixture tmp_dir repo codex_stub stdout_path stderr_path worktree_path
  fixture=$(setup_fixture "$task_id")
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  codex_stub=$(printf '%s\n' "$fixture" | sed -n '3p')
  stdout_path="$tmp_dir/stdout.log"
  stderr_path="$tmp_dir/stderr.log"
  worktree_path="$repo/.worktrees/$task_id"

  run_wrapper "$repo" "$codex_stub" "$task_id" "$stdout_path" "$stderr_path" --keep-worktree

  assert_exists "$worktree_path" "--keep-worktree should preserve worktree"
  assert_contains "$stderr_path" "cleanup_status=kept" "--keep-worktree should log kept status"
  rm -rf "$tmp_dir"
}

run_test() {
  local name="$1"
  if "$name"; then
    pass_count=$((pass_count + 1))
    printf 'ok - %s\n' "$name"
  else
    fail_count=$((fail_count + 1))
    printf 'not ok - %s\n' "$name" >&2
  fi
}

main() {
  run_test test_default_preserve
  run_test test_cleanup_without_manifest_quarantines
  run_test test_invalid_manifest_quarantines
  run_test test_valid_manifest_allows_cleanup
  run_test test_existing_keep_worktree_compat

  printf 'day0 cleanup tests: %s passed, %s failed\n' "$pass_count" "$fail_count"
  [ "$fail_count" -eq 0 ]
}

main "$@"
