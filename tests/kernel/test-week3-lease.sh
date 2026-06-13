#!/usr/bin/env bash
# Week 3 lease registry and Lease Before Write invariant tests
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
ACQUIRE=${ACQUIRE:-"$REPO_ROOT/scripts/org/acquire-lease.sh"}
RELEASE=${RELEASE:-"$REPO_ROOT/scripts/org/release-lease.sh"}
LIST=${LIST:-"$REPO_ROOT/scripts/org/list-leases.sh"}
POLICY=${POLICY:-"$REPO_ROOT/.claude/hooks/pretool_policy.py"}
SCHEMA=${SCHEMA:-"$REPO_ROOT/.claude/schemas/lease.v1.json"}

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

setup_repo_fixture() {
  local tmp_dir repo
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-week3-lease.XXXXXX")
  repo="$tmp_dir/repo"
  mkdir -p "$repo/scripts/org" "$repo/.claude/hooks" "$repo/.claude/schemas" "$repo/.ai/_machine/leases"
  cp "$ACQUIRE" "$repo/scripts/org/acquire-lease.sh"
  cp "$RELEASE" "$repo/scripts/org/release-lease.sh"
  cp "$LIST" "$repo/scripts/org/list-leases.sh"
  cp "$POLICY" "$repo/.claude/hooks/pretool_policy.py"
  cp "$REPO_ROOT/.claude/hooks/policy_core.py" "$repo/.claude/hooks/policy_core.py"
  cp "$SCHEMA" "$repo/.claude/schemas/lease.v1.json"
  chmod +x "$repo/scripts/org/acquire-lease.sh" "$repo/scripts/org/release-lease.sh" "$repo/scripts/org/list-leases.sh"
  printf '%s\n%s\n' "$tmp_dir" "$repo"
}

write_fixture() {
  local fixture_path="$1"
  local tool="$2"
  local path="$3"
  local cwd="$4"

  python3 - "$fixture_path" "$tool" "$path" "$cwd" <<'PY'
import json
import sys

fixture_path, tool, path, cwd = sys.argv[1:5]
with open(fixture_path, "w", encoding="utf-8") as handle:
    json.dump({"tool": tool, "path": path, "cwd": cwd}, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
}

test_lease_schema_valid_json() {
  python3 - "$SCHEMA" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    schema = json.load(handle)
assert schema["$id"] == "orgos.lease.v1"
assert "lease_id" in schema["properties"]
assert "allowed_paths" in schema["required"]
PY
}

test_acquire_lease_basic() {
  local fixture tmp_dir repo lease_id lease_path
  fixture=$(setup_repo_fixture)
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')

  lease_id=$("$repo/scripts/org/acquire-lease.sh" --task-id T-TEST-1 --actor-role codex --actor-id kernel --allowed-paths "src/auth/")
  lease_path="$repo/.ai/_machine/leases/$lease_id.json"

  assert_exists "$lease_path" "acquire should create lease file"
  python3 - "$lease_path" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    lease = json.load(handle)
assert lease["schema_version"] == "orgos.lease.v1"
assert lease["status"] == "active"
assert lease["allowed_paths"] == ["src/auth/"]
PY
  rm -rf "$tmp_dir"
}

test_acquire_rejects_overlapping_lease() {
  local fixture tmp_dir repo status stderr_path
  fixture=$(setup_repo_fixture)
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  stderr_path="$tmp_dir/stderr.log"

  "$repo/scripts/org/acquire-lease.sh" --task-id T-TEST-1 --actor-role codex --actor-id kernel --allowed-paths "src/auth/" >/dev/null
  set +e
  "$repo/scripts/org/acquire-lease.sh" --task-id T-TEST-2 --actor-role codex --actor-id kernel --allowed-paths "src/auth/login.ts" >/dev/null 2>"$stderr_path"
  status=$?
  set -e

  [ "$status" -eq 3 ] || fail "overlapping lease should exit 3, got $status"
  assert_contains "$stderr_path" "lease conflict detected" "overlap should report conflict"
  rm -rf "$tmp_dir"
}

test_release_lease() {
  local fixture tmp_dir repo lease_id released_path
  fixture=$(setup_repo_fixture)
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')

  lease_id=$("$repo/scripts/org/acquire-lease.sh" --task-id T-TEST-3 --actor-role codex --actor-id kernel --allowed-paths "src/auth/")
  released_path=$("$repo/scripts/org/release-lease.sh" "$lease_id")

  assert_exists "$released_path" "release should move lease into history"
  [ ! -e "$repo/.ai/_machine/leases/$lease_id.json" ] || fail "release should remove active lease"
  python3 - "$released_path" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    lease = json.load(handle)
assert lease["status"] == "released"
assert "released_at" in lease
PY
  rm -rf "$tmp_dir"
}

test_expired_lease_garbage_collected() {
  local fixture tmp_dir repo lease_id lease_path output_path
  fixture=$(setup_repo_fixture)
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  output_path="$tmp_dir/list.out"

  lease_id=$("$repo/scripts/org/acquire-lease.sh" --task-id T-TEST-4 --actor-role codex --actor-id kernel --allowed-paths "src/auth/" --ttl-seconds 1)
  lease_path="$repo/.ai/_machine/leases/$lease_id.json"
  sleep 2
  "$repo/scripts/org/list-leases.sh" --include-expired >"$output_path"

  python3 - "$lease_path" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    lease = json.load(handle)
assert lease["status"] == "expired"
PY
  assert_contains "$output_path" "$lease_id" "expired lease should be listed when requested"
  rm -rf "$tmp_dir"
}

test_pretool_blocks_write_without_lease() {
  local fixture tmp_dir repo fixture_path stderr_path status
  fixture=$(setup_repo_fixture)
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  fixture_path="$tmp_dir/fixture.json"
  stderr_path="$tmp_dir/stderr.log"
  write_fixture "$fixture_path" Edit "src/auth/login.ts" "$repo"

  set +e
  ORGOS_KERNEL_MODE_OVERRIDE=enforce python3 "$repo/.claude/hooks/pretool_policy.py" --test-fixture "$fixture_path" 2>"$stderr_path"
  status=$?
  set -e

  [ "$status" -eq 2 ] || fail "write without lease should exit 2, got $status"
  assert_contains "$stderr_path" "LeaseBeforeWrite" "policy should report lease invariant"
  rm -rf "$tmp_dir"
}

test_pretool_allows_write_with_lease() {
  local fixture tmp_dir repo fixture_path status
  fixture=$(setup_repo_fixture)
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  repo=$(printf '%s\n' "$fixture" | sed -n '2p')
  fixture_path="$tmp_dir/fixture.json"

  "$repo/scripts/org/acquire-lease.sh" --task-id T-TEST-5 --actor-role codex --actor-id kernel --allowed-paths "src/auth/" >/dev/null
  write_fixture "$fixture_path" Edit "src/auth/login.ts" "$repo"

  set +e
  ORGOS_KERNEL_MODE_OVERRIDE=enforce python3 "$repo/.claude/hooks/pretool_policy.py" --test-fixture "$fixture_path"
  status=$?
  set -e

  [ "$status" -eq 0 ] || fail "write with covering lease should pass, got $status"
  rm -rf "$tmp_dir"
}

test_krt_008_lease_conflict() {
  test_acquire_rejects_overlapping_lease
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
      run_test test_lease_schema_valid_json
      run_test test_acquire_lease_basic
      run_test test_acquire_rejects_overlapping_lease
      run_test test_release_lease
      run_test test_expired_lease_garbage_collected
      run_test test_pretool_blocks_write_without_lease
      run_test test_pretool_allows_write_with_lease
      run_test test_krt_008_lease_conflict
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac

  printf 'Week3 lease tests: %s passed, %s failed\n' "$pass_count" "$fail_count"
  [ "$fail_count" -eq 0 ]
}

main "$@"
