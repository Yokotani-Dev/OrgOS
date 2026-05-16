#!/usr/bin/env bash
# Secret helper tests using a mock macOS Keychain command.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
SECRET_GET=${SECRET_GET:-"$REPO_ROOT/scripts/org/secret-get.sh"}
SECRET_SET=${SECRET_SET:-"$REPO_ROOT/scripts/org/secret-set.sh"}

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
  grep -Fq -- "$needle" "$path" || fail "$msg: expected '$needle' in $path"
}

setup_mock_keychain() {
  local tmp_dir bin_dir mock_security db_dir
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-secret-management.XXXXXX")
  bin_dir="$tmp_dir/bin"
  db_dir="$tmp_dir/keychain"
  mock_security="$bin_dir/security"
  mkdir -p "$bin_dir" "$db_dir"

  cat >"$mock_security" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

db_dir="${ORGOS_MOCK_KEYCHAIN_DB:?ORGOS_MOCK_KEYCHAIN_DB is required}"
command_name="${1:-}"
shift || true

service=""
account=""
secret=""
want_password=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    -s)
      service="${2:-}"
      shift 2
      ;;
    -a)
      account="${2:-}"
      shift 2
      ;;
    -w)
      if [ "$command_name" = "add-generic-password" ]; then
        secret="${2:-}"
        shift 2
      else
        want_password=1
        shift
      fi
      ;;
    -U)
      shift
      ;;
    *)
      echo "mock security: unknown argument: $1" >&2
      exit 64
      ;;
  esac
done

key_path() {
  python3 - "$db_dir" "$service" "$account" <<'PY'
import hashlib
import sys
from pathlib import Path

db_dir, service, account = sys.argv[1:4]
key = hashlib.sha256(f"{service}\0{account}".encode("utf-8")).hexdigest()
print(Path(db_dir) / key)
PY
}

case "$command_name" in
  add-generic-password)
    if [ -z "$service" ] || [ -z "$account" ] || [ -z "$secret" ]; then
      echo "mock security: service, account, and password are required" >&2
      exit 64
    fi
    printf '%s' "$secret" >"$(key_path)"
    ;;
  find-generic-password)
    if [ -z "$service" ] || [ -z "$account" ] || [ "$want_password" -ne 1 ]; then
      echo "mock security: service, account, and -w are required" >&2
      exit 64
    fi
    path="$(key_path)"
    if [ ! -f "$path" ]; then
      echo "mock security: item not found" >&2
      exit 44
    fi
    cat "$path"
    ;;
  *)
    echo "mock security: unsupported command: $command_name" >&2
    exit 64
    ;;
esac
EOF
  chmod +x "$mock_security"

  printf '%s\n%s\n%s\n' "$tmp_dir" "$bin_dir" "$db_dir"
}

with_mock_keychain() {
  local fixture tmp_dir bin_dir db_dir had_errexit
  had_errexit=0
  case "$-" in
    *e*) had_errexit=1 ;;
  esac
  fixture=$(setup_mock_keychain)
  tmp_dir=$(printf '%s\n' "$fixture" | sed -n '1p')
  bin_dir=$(printf '%s\n' "$fixture" | sed -n '2p')
  db_dir=$(printf '%s\n' "$fixture" | sed -n '3p')

  set +e
  PATH="$bin_dir:$PATH" ORGOS_MOCK_KEYCHAIN_DB="$db_dir" "$@"
  local status=$?
  rm -rf "$tmp_dir"
  if [ "$had_errexit" -eq 1 ]; then
    set -e
  fi
  return "$status"
}

test_secret_get_returns_stored_secret() {
  local output output_path
  output_path=$(mktemp "${TMPDIR:-/tmp}/orgos-secret-get.XXXXXX")
  # shellcheck disable=SC2016
  with_mock_keychain bash -c '
    printf "%s" "test-secret-value" | "$1" orgos/test default --read-stdin
    "$2" orgos/test default
  ' bash "$SECRET_SET" "$SECRET_GET" >"$output_path"
  output=$(cat "$output_path")
  [ "$output" = "test-secret-value" ] || fail "secret-get should return stored secret"
  rm -f "$output_path"
}

test_secret_set_updates_existing_entry() {
  local output output_path
  output_path=$(mktemp "${TMPDIR:-/tmp}/orgos-secret-update.XXXXXX")
  # shellcheck disable=SC2016
  with_mock_keychain bash -c '
    printf "%s" "first-value" | "$1" orgos/test default --read-stdin
    printf "%s" "second-value" | "$1" orgos/test default --read-stdin
    "$2" orgos/test default
  ' bash "$SECRET_SET" "$SECRET_GET" >"$output_path"
  output=$(cat "$output_path")
  [ "$output" = "second-value" ] || fail "secret-set should update existing entry"
  rm -f "$output_path"
}

test_secret_get_missing_entry_exits_nonzero() {
  local status stderr_path
  stderr_path=$(mktemp "${TMPDIR:-/tmp}/orgos-secret-missing.XXXXXX")
  set +e
  with_mock_keychain "$SECRET_GET" orgos/test missing >/dev/null 2>"$stderr_path"
  status=$?
  set -e
  [ "$status" -ne 0 ] || fail "secret-get should fail for missing entry"
  assert_contains "$stderr_path" "item not found" "missing entry should report keychain failure"
  rm -f "$stderr_path"
}

test_secret_set_rejects_empty_secret() {
  local status stderr_path
  stderr_path=$(mktemp "${TMPDIR:-/tmp}/orgos-secret-empty.XXXXXX")
  set +e
  # shellcheck disable=SC2016
  with_mock_keychain bash -c 'printf "" | "$1" orgos/test default --read-stdin' bash "$SECRET_SET" 2>"$stderr_path"
  status=$?
  set -e
  [ "$status" -eq 2 ] || fail "empty secret should exit 2, got $status"
  assert_contains "$stderr_path" "secret must be non-empty" "empty secret should be explained"
  rm -f "$stderr_path"
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
      run_test test_secret_get_returns_stored_secret
      run_test test_secret_set_updates_existing_entry
      run_test test_secret_get_missing_entry_exits_nonzero
      run_test test_secret_set_rejects_empty_secret
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac

  printf 'Secret management tests: %s passed, %s failed\n' "$pass_count" "$fail_count"
  [ "$fail_count" -eq 0 ]
}

main "$@"
