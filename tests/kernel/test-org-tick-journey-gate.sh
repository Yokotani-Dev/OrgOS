#!/usr/bin/env bash
# Regression test for /org-tick REQUIREMENTS -> DESIGN Journey gate.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
ORG_TICK="$REPO_ROOT/.claude/commands/org-tick.md"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local needle="$1"
  local msg="$2"
  grep -Fq "$needle" "$ORG_TICK" || fail "$msg: expected '$needle' in $ORG_TICK"
}

assert_contains "ORG_TICK_JOURNEY_GATE_SENTINEL" "journey gate sentinel"
assert_contains "REQUIREMENTS -> DESIGN" "requirements to design transition"
assert_contains ".ai/JOURNEY.md" "journey source path"
assert_contains "sync_status=confirmed" "confirmed journey status"
assert_contains "Journey workshop" "owner journey workshop prompt"

printf 'ok - org-tick Journey gate sentinel present\n'
