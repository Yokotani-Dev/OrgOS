#!/usr/bin/env bash
# Script consolidation regression tests.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
RUNNER="$SCRIPT_DIR/run-kernel-tests.sh"
DECISIONS="$REPO_ROOT/.ai/DECISIONS.md"

pass_count=0
fail_count=0
current_test_failed=0

fail() {
  printf 'not ok - %s\n' "$1" >&2
  current_test_failed=1
  return 1
}

test_no_script_backups_remain() {
  local backups
  backups=$(find "$REPO_ROOT/scripts" -type f \( -name '*.bak' -o -name '*.old' \) -print)
  [ -z "$backups" ] || fail "scripts/ should not contain .bak or .old files: $backups"
}

test_kernel_runner_references_exist() {
  local referenced_script missing=0
  while IFS= read -r referenced_script; do
    if [ ! -f "$SCRIPT_DIR/$referenced_script" ]; then
      printf 'missing kernel runner reference: %s\n' "$referenced_script" >&2
      missing=1
    fi
  done < <(sed -n 's|^[[:space:]]*bash "\$SCRIPT_DIR/\([^"]*\)".*|\1|p' "$RUNNER")

  [ "$missing" -eq 0 ] || fail "all run-kernel-tests.sh references should exist"
}

test_decisions_documents_script_count() {
  # The T-OS-461 audit snapshot is pinned in DECISIONS.md. DECISIONS.md is
  # kernel-protected (Manager append only; worker edits are hook-denied), so
  # this regression validates that the audit record exists and documents a
  # count — not that it tracks every later script addition, which would
  # require a protected-file edit whenever any script is legitimately added.
  grep -Fq "T-OS-461" "$DECISIONS" || fail "DECISIONS.md should mention T-OS-461"
  grep -Eq "Total scripts count: [0-9]+ files" "$DECISIONS" || \
    fail "DECISIONS.md should document the scripts/ file count audited in T-OS-461"
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
      run_test test_no_script_backups_remain
      run_test test_kernel_runner_references_exist
      run_test test_decisions_documents_script_count
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac

  printf '# script-consolidation tests: %d passed, %d failed\n' "$pass_count" "$fail_count"
  [ "$fail_count" -eq 0 ]
}

main "$@"
