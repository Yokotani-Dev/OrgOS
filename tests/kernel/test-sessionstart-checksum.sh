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

# --- ISS-008 regression tests -------------------------------------------
# These tests intentionally avoid env injection so that wiring breakage
# (unregistered hook, wrong default verifier path, silent fallback) is caught.

test_sessionstart_hook_is_executable() {
  [ -x "$SESSIONSTART_HOOK" ] || fail "SessionStart.sh must have the executable bit (chmod +x)"
}

test_sessionstart_registered_in_settings() {
  local settings="$REPO_ROOT/.claude/settings.json"
  [ -f "$settings" ] || fail "settings.json not found at $settings"
  python3 - "$settings" <<'EOF_PY' || fail "SessionStart.sh is not registered as a SessionStart hook in .claude/settings.json"
import json, sys
data = json.load(open(sys.argv[1]))
entries = data.get("hooks", {}).get("SessionStart", [])
commands = [h.get("command", "") for e in entries for h in e.get("hooks", [])]
sys.exit(0 if any(".claude/hooks/SessionStart.sh" in c for c in commands) else 1)
EOF_PY
}

test_default_verifier_path_exists_on_disk() {
  # Parse the default straight from the hook source — no env override allowed
  # to mask a wrong path (the original ISS-008 failure mode).
  local default_line
  default_line=$(grep -E '^DEFAULT_CHECKSUM_VERIFIER=' "$SESSIONSTART_HOOK" || true)
  [ -n "$default_line" ] || fail "DEFAULT_CHECKSUM_VERIFIER assignment not found in SessionStart.sh"
  printf '%s\n' "$default_line" | grep -Fq 'scripts/org/check-generated-checksums.py' \
    || fail "default verifier must point at scripts/org/check-generated-checksums.py, got: $default_line"
  [ -f "$REPO_ROOT/scripts/org/check-generated-checksums.py" ] \
    || fail "default verifier missing on disk: $REPO_ROOT/scripts/org/check-generated-checksums.py"
}

test_sessionstart_warns_when_verifier_missing() {
  local tmp_dir output_path status
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-sessionstart-checksum.XXXXXX")
  output_path="$tmp_dir/output"

  set +e
  ORGOS_GENERATED_CHECKSUM_VERIFIER="$tmp_dir/does-not-exist.py" \
    bash "$SESSIONSTART_HOOK" >"$output_path" 2>&1
  status=$?
  set -e

  [ "$status" -eq 0 ] || fail "SessionStart should remain warn-only when verifier is missing, got $status"
  assert_contains "$output_path" "checksum verifier not found" "missing verifier must produce a visible warning (no silent return 0)"
  rm -rf "$tmp_dir"
}

test_sessionstart_end_to_end_default_verifier() {
  # Run with NO env injection: the hook must locate the real verifier on disk.
  local tmp_dir output_path status
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-sessionstart-checksum.XXXXXX")
  output_path="$tmp_dir/output"

  set +e
  env -u ORGOS_GENERATED_CHECKSUM_VERIFIER bash "$SESSIONSTART_HOOK" >"$output_path" 2>&1
  status=$?
  set -e

  [ "$status" -eq 0 ] || fail "SessionStart end-to-end run should exit 0, got $status"
  assert_contains "$output_path" "OrgOS SessionStart:" "end-to-end run should produce session banner"
  assert_not_contains "$output_path" "checksum verifier not found" "default verifier must be found on disk (no fallback warning)"
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
      run_test test_sessionstart_hook_is_executable
      run_test test_sessionstart_registered_in_settings
      run_test test_default_verifier_path_exists_on_disk
      run_test test_sessionstart_warns_when_verifier_missing
      run_test test_sessionstart_end_to_end_default_verifier
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
