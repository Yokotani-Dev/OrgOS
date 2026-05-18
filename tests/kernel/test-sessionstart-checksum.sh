#!/usr/bin/env bash
# SessionStart checksum verifier regression tests.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
SESSIONSTART_HOOK=${SESSIONSTART_HOOK:-"$REPO_ROOT/.claude/hooks/SessionStart.sh"}

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

assert_not_contains() {
  local path="$1"
  local needle="$2"
  local msg="$3"
  ! grep -Fq -- "$needle" "$path" || fail "$msg: did not expect '$needle' in $path"
}

make_verifier() {
  local tmp_dir="$1"
  local exit_code="$2"
  local message="$3"
  local verifier="$tmp_dir/check-generated-checksums.py"

  cat >"$verifier" <<EOF_VERIFIER
#!/usr/bin/env bash
set -euo pipefail
printf 'ran\n' >"\${ORGOS_TEST_MARKER:?ORGOS_TEST_MARKER is required}"
printf '%s\n' "$message"
exit "$exit_code"
EOF_VERIFIER
  chmod +x "$verifier"
  printf '%s\n' "$verifier"
}

run_sessionstart_with_verifier() {
  local verifier="$1"
  local marker="$2"
  local output_path="$3"

  set +e
  ORGOS_GENERATED_CHECKSUM_VERIFIER="$verifier" \
    ORGOS_TEST_MARKER="$marker" \
    bash "$SESSIONSTART_HOOK" >"$output_path" 2>&1
  local status=$?
  set -e
  return "$status"
}

test_sessionstart_runs_checksum_verifier() {
  local tmp_dir verifier marker output_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-sessionstart-checksum.XXXXXX")
  marker="$tmp_dir/marker"
  output_path="$tmp_dir/output"
  verifier=$(make_verifier "$tmp_dir" 0 "checksums ok")

  run_sessionstart_with_verifier "$verifier" "$marker" "$output_path"
  local status=$?

  [ "$status" -eq 0 ] || fail "SessionStart should exit 0 when checksum verifier passes, got $status"
  [ -f "$marker" ] || fail "checksum verifier should be executed"
  assert_not_contains "$output_path" "Owner warning: generated checksum mismatch detected" "passing checksum should not warn Owner"
  rm -rf "$tmp_dir"
}

test_sessionstart_warns_owner_on_checksum_mismatch() {
  local tmp_dir verifier marker output_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-sessionstart-checksum.XXXXXX")
  marker="$tmp_dir/marker"
  output_path="$tmp_dir/output"
  verifier=$(make_verifier "$tmp_dir" 1 "checksum mismatch: .ai/GLOSSARY.generated.md")

  run_sessionstart_with_verifier "$verifier" "$marker" "$output_path"
  local status=$?

  [ "$status" -eq 0 ] || fail "SessionStart should remain warn-only on mismatch, got $status"
  [ -f "$marker" ] || fail "checksum verifier should be executed before warning"
  assert_contains "$output_path" "Owner warning: generated checksum mismatch detected" "checksum mismatch should warn Owner"
  assert_contains "$output_path" "checksum mismatch: .ai/GLOSSARY.generated.md" "verifier output should be shown"
  assert_contains "$output_path" "Session continues (warn only)." "mismatch should not block session start"
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
      run_test test_sessionstart_runs_checksum_verifier
      run_test test_sessionstart_warns_owner_on_checksum_mismatch
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac

  printf '# SessionStart checksum tests: %d passed, %d failed\n' "$pass_count" "$fail_count"
  [ "$fail_count" -eq 0 ]
}

main "$@"
