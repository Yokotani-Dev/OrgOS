#!/usr/bin/env bash
# Baseline worker reading invariants.
# Codex auto-loads AGENTS.md on every run, so baseline docs that every worker
# must read are delivered via AGENTS.md (the auto-loaded channel) rather than
# transcribed per Work Order. This test mechanically guards that channel:
# - AGENTS.md references each baseline doc
# - each referenced baseline doc exists on disk
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
AGENTS_FILE="$REPO_ROOT/AGENTS.md"

# Baseline docs that AGENTS.md must reference and that must exist.
BASELINE_DOCS=(
  ".claude/agents/CODEX_WORKER_GUIDE.md"
  ".claude/skills/karpathy-guidelines.md"
  ".claude/skills/review-criteria.md"
  ".claude/skills/security.md"
)

pass_count=0
fail_count=0
current_test_failed=0

fail() {
  printf 'not ok - %s\n' "$1" >&2
  current_test_failed=1
}

run_test() {
  local name="$1"
  current_test_failed=0
  "$name"
  if [ "$current_test_failed" -eq 0 ]; then
    printf 'ok - %s\n' "$name"
    pass_count=$((pass_count + 1))
  else
    fail_count=$((fail_count + 1))
  fi
}

test_agents_file_exists() {
  [ -f "$AGENTS_FILE" ] || fail "AGENTS.md missing: $AGENTS_FILE"
}

test_agents_references_each_baseline_doc() {
  local doc
  for doc in "${BASELINE_DOCS[@]}"; do
    grep -qF "$doc" "$AGENTS_FILE" || fail "AGENTS.md does not reference baseline doc: $doc"
  done
}

test_each_baseline_doc_exists() {
  local doc
  for doc in "${BASELINE_DOCS[@]}"; do
    [ -f "$REPO_ROOT/$doc" ] || fail "baseline doc missing on disk: $doc"
  done
}

run_test test_agents_file_exists
run_test test_agents_references_each_baseline_doc
run_test test_each_baseline_doc_exists

printf 'baseline refs tests: %d passed, %d failed\n' "$pass_count" "$fail_count"
[ "$fail_count" -eq 0 ]
