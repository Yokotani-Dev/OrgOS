#!/usr/bin/env bash
# Generated view checksum verification tests.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
CHECKSUM_VERIFIER=${CHECKSUM_VERIFIER:-"$REPO_ROOT/scripts/org/check-generated-checksums.py"}

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

sha256_of() {
  shasum -a 256 "$1" | awk '{print $1}'
}

make_repo() {
  local tmp_dir="$1"
  mkdir -p "$tmp_dir/.ai"
}

create_checksum_db() {
  local db_path="$1"
  shift
  python3 - "$db_path" "$@" <<'PY'
import sqlite3
import sys

db_path = sys.argv[1]
pairs = sys.argv[2:]
with sqlite3.connect(db_path) as connection:
    connection.execute(
        """
        CREATE TABLE view_checksums (
          path TEXT PRIMARY KEY,
          sha256 TEXT NOT NULL,
          source_event_seq INTEGER NOT NULL,
          generated_at TEXT NOT NULL
        )
        """
    )
    for item in pairs:
        path, sha256 = item.split("=", 1)
        connection.execute(
            "INSERT INTO view_checksums(path, sha256, source_event_seq, generated_at) VALUES (?, ?, 1, '2026-05-17T00:00:00Z')",
            (path, sha256),
        )
PY
}

test_script_is_executable() {
  [ -x "$CHECKSUM_VERIFIER" ] || fail "checksum verifier should be executable"
}

test_matching_generated_checksums_pass() {
  local tmp_dir glossary tasks stdout_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-checksum-verify.XXXXXX")
  make_repo "$tmp_dir"
  glossary="$tmp_dir/.ai/GLOSSARY.generated.md"
  tasks="$tmp_dir/.ai/TASKS.generated.yaml"
  stdout_path="$tmp_dir/stdout.log"
  printf '# glossary\n' > "$glossary"
  printf 'tasks: []\n' > "$tasks"
  create_checksum_db "$tmp_dir/.ai/orgos.sqlite" \
    ".ai/GLOSSARY.generated.md=$(sha256_of "$glossary")" \
    ".ai/TASKS.generated.yaml=$(sha256_of "$tasks")"

  "$CHECKSUM_VERIFIER" --repo-root "$tmp_dir" >"$stdout_path"

  assert_contains "$stdout_path" "ok - verified 2 generated checksum(s)" "matching generated checksums should pass"
  rm -rf "$tmp_dir"
}

test_mismatch_exits_one_and_lists_file() {
  local tmp_dir glossary stderr_path status
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-checksum-verify.XXXXXX")
  make_repo "$tmp_dir"
  glossary="$tmp_dir/.ai/GLOSSARY.generated.md"
  stderr_path="$tmp_dir/stderr.log"
  printf '# glossary\n' > "$glossary"
  create_checksum_db "$tmp_dir/.ai/orgos.sqlite" \
    ".ai/GLOSSARY.generated.md=0000000000000000000000000000000000000000000000000000000000000000"

  set +e
  "$CHECKSUM_VERIFIER" --repo-root "$tmp_dir" 2>"$stderr_path"
  status=$?
  set -e

  [ "$status" -eq 1 ] || fail "checksum mismatch should exit 1"
  assert_contains "$stderr_path" ".ai/GLOSSARY.generated.md" "mismatched file should be listed"
  assert_contains "$stderr_path" "checksum mismatch" "mismatch reason should be reported"
  rm -rf "$tmp_dir"
}

test_missing_checksum_row_fails() {
  local tmp_dir decisions stderr_path status
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-checksum-verify.XXXXXX")
  make_repo "$tmp_dir"
  decisions="$tmp_dir/.ai/DECISIONS.generated.md"
  stderr_path="$tmp_dir/stderr.log"
  printf '# decisions\n' > "$decisions"
  create_checksum_db "$tmp_dir/.ai/orgos.sqlite"

  set +e
  "$CHECKSUM_VERIFIER" --repo-root "$tmp_dir" 2>"$stderr_path"
  status=$?
  set -e

  [ "$status" -eq 1 ] || fail "missing checksum row should exit 1"
  assert_contains "$stderr_path" ".ai/DECISIONS.generated.md" "file with missing row should be listed"
  assert_contains "$stderr_path" "missing row in view_checksums" "missing row reason should be reported"
  rm -rf "$tmp_dir"
}

test_missing_generated_files_are_skipped() {
  local tmp_dir stdout_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-checksum-verify.XXXXXX")
  make_repo "$tmp_dir"
  stdout_path="$tmp_dir/stdout.log"
  create_checksum_db "$tmp_dir/.ai/orgos.sqlite"

  "$CHECKSUM_VERIFIER" --repo-root "$tmp_dir" >"$stdout_path"

  assert_contains "$stdout_path" "ok - no generated files present" "missing generated files should be skipped"
  rm -rf "$tmp_dir"
}

test_sha256_prefix_is_accepted() {
  local tmp_dir dashboard stdout_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-checksum-verify.XXXXXX")
  make_repo "$tmp_dir"
  dashboard="$tmp_dir/.ai/DASHBOARD.generated.md"
  stdout_path="$tmp_dir/stdout.log"
  printf '# dashboard\n' > "$dashboard"
  create_checksum_db "$tmp_dir/.ai/orgos.sqlite" \
    ".ai/DASHBOARD.generated.md=sha256:$(sha256_of "$dashboard")"

  "$CHECKSUM_VERIFIER" --repo-root "$tmp_dir" >"$stdout_path"

  assert_contains "$stdout_path" "ok - verified 1 generated checksum(s)" "sha256 prefix should be accepted"
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
      run_test test_script_is_executable
      run_test test_matching_generated_checksums_pass
      run_test test_mismatch_exits_one_and_lists_file
      run_test test_missing_checksum_row_fails
      run_test test_missing_generated_files_are_skipped
      run_test test_sha256_prefix_is_accepted
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac

  printf '# checksum-verify tests: %d passed, %d failed\n' "$pass_count" "$fail_count"
  [ "$fail_count" -eq 0 ]
}

main "$@"
