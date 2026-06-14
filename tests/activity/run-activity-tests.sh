#!/usr/bin/env bash
# Central Activity Ledger test suite runner (T-OS-483).
# Mirrors tests/kernel/run-kernel-tests.sh conventions, but runs every test
# file even after a failure and reports PASS/FAIL per file + SUITE_EXIT.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

tests="
test-log-event.sh
test-journal.sh
test-bridge.sh
test-concurrent-append.sh
test-mcp-server.sh
test-session-summary.sh
test-bridge-enrichment.sh
test-journal-denoise.sh
"

suite_exit=0
pass_count=0
fail_count=0

for t in $tests; do
  printf '=== %s ===\n' "$t"
  if bash "$SCRIPT_DIR/$t"; then
    pass_count=$((pass_count + 1))
    printf 'PASS - %s\n' "$t"
  else
    fail_count=$((fail_count + 1))
    suite_exit=1
    printf 'FAIL - %s\n' "$t" >&2
  fi
done

printf 'Activity suite: %s file(s) passed, %s file(s) failed\n' "$pass_count" "$fail_count"
printf 'SUITE_EXIT=%s\n' "$suite_exit"
exit "$suite_exit"
