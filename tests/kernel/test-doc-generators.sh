#!/usr/bin/env bash
# Documentation generator regression tests.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
GLOSSARY_GENERATOR=${GLOSSARY_GENERATOR:-"$REPO_ROOT/scripts/org/generate-glossary.py"}
DECISIONS_TOC_GENERATOR=${DECISIONS_TOC_GENERATOR:-"$REPO_ROOT/scripts/org/generate-decisions-toc.py"}

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

assert_nonempty() {
  local path="$1"
  local msg="$2"
  [ -s "$path" ] || fail "$msg: $path should be non-empty"
}

setup_glossary_fixture() {
  local repo="$1"
  mkdir -p "$repo/.claude/rules" "$repo/.ai/REVIEW/T-OS-400"
  cat > "$repo/.claude/rules/kernel.md" <<'EOF_RULE'
# Lease Before Write Protocol - Iron Law

## Constitutional Invariant

Workers must respect allowed_paths and keep a per-task worktree.
The Integrator owns commits, and the Owner approves irreversible operations.
EOF_RULE
  cat > "$repo/.ai/REVIEW/T-OS-400/SYNTHESIS.md" <<'EOF_SYNTHESIS'
# Kernel Synthesis

## Event Log and Projection

Plan Contract, Policy Core, pretool, posttool, and artifact manifest rules are kernel-v2 terms.
EOF_SYNTHESIS
}

setup_decisions_fixture() {
  local path="$1"
  cat > "$path" <<'EOF_DECISIONS'
# DECISIONS

> Decisions are recorded here.

---

## Pending (Owner Review)

None.

## PLAN-UPDATE-001: First Plan

Details.

## PLAN-UPDATE-001: First Plan

Duplicate title for anchor stability.
EOF_DECISIONS
}

test_scripts_are_executable() {
  [ -x "$GLOSSARY_GENERATOR" ] || fail "glossary generator should be executable"
  [ -x "$DECISIONS_TOC_GENERATOR" ] || fail "decisions TOC generator should be executable"
}

test_glossary_generator_outputs_terms() {
  local tmp_dir repo output_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-doc-generators.XXXXXX")
  repo="$tmp_dir/repo"
  output_path="$tmp_dir/GLOSSARY.generated.md"
  setup_glossary_fixture "$repo"

  "$GLOSSARY_GENERATOR" --repo-root "$repo" --output "$output_path" >/dev/null

  assert_nonempty "$output_path" "glossary output"
  assert_contains "$output_path" "**Constitutional Invariant**" "glossary should include invariant"
  assert_contains "$output_path" "**Integrator**" "glossary should include integrator"
  assert_contains "$output_path" "**Lease**" "glossary should include lease"
  rm -rf "$tmp_dir"
}

test_decisions_toc_generator_outputs_toc() {
  local tmp_dir decisions_path
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-doc-generators.XXXXXX")
  decisions_path="$tmp_dir/DECISIONS.md"
  setup_decisions_fixture "$decisions_path"

  "$DECISIONS_TOC_GENERATOR" --file "$decisions_path" >/dev/null

  assert_contains "$decisions_path" "<!-- TOC start -->" "TOC start marker"
  assert_contains "$decisions_path" "<!-- TOC end -->" "TOC end marker"
  assert_contains "$decisions_path" "- [Pending (Owner Review)](#pending-owner-review)" "pending heading anchor"
  assert_contains "$decisions_path" "- [PLAN-UPDATE-001: First Plan](#plan-update-001-first-plan-1)" "duplicate heading anchor"
  rm -rf "$tmp_dir"
}

test_decisions_toc_generator_is_idempotent() {
  local tmp_dir decisions_path before_hash after_hash
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/orgos-doc-generators.XXXXXX")
  decisions_path="$tmp_dir/DECISIONS.md"
  setup_decisions_fixture "$decisions_path"

  "$DECISIONS_TOC_GENERATOR" --file "$decisions_path" >/dev/null
  before_hash=$(shasum -a 256 "$decisions_path" | awk '{print $1}')
  "$DECISIONS_TOC_GENERATOR" --file "$decisions_path" >/dev/null
  after_hash=$(shasum -a 256 "$decisions_path" | awk '{print $1}')

  [ "$before_hash" = "$after_hash" ] || fail "TOC regeneration should be idempotent"
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
      run_test test_scripts_are_executable
      run_test test_glossary_generator_outputs_terms
      run_test test_decisions_toc_generator_outputs_toc
      run_test test_decisions_toc_generator_is_idempotent
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac

  printf '# doc-generator tests: %d passed, %d failed\n' "$pass_count" "$fail_count"
  [ "$fail_count" -eq 0 ]
}

main "$@"
