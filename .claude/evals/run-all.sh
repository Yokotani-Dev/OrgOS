#!/usr/bin/env bash
# OrgOS Evals Runner
# Usage:
#   ./run-all.sh                    # Run all evals
#   ./run-all.sh --changed-files f1 f2 ...  # Run with changed file list (for OIP PR eval)
#   ./run-all.sh --json             # Output JSON format
#
# Exit codes:
#   0 = all pass
#   1 = one or more failures

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Parse arguments
CHANGED_FILES=()
JSON_OUTPUT=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --changed-files)
      shift
      while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
        CHANGED_FILES+=("$1")
        shift
      done
      ;;
    --json)
      JSON_OUTPUT=true
      shift
      ;;
    *)
      shift
      ;;
  esac
done

export REPO_ROOT
export CHANGED_FILES_STR="${CHANGED_FILES[*]:-}"

PASS=0
FAIL=0
WARN=0
RESULTS=()

run_eval() {
  local name="$1"
  local script="$2"

  if [[ ! -x "$script" ]]; then
    chmod +x "$script"
  fi

  local output
  local exit_code=0
  output=$("$script" 2>&1) || exit_code=$?

  local status="pass"
  if [[ $exit_code -eq 1 ]]; then
    status="fail"
    ((FAIL++))
  elif [[ $exit_code -eq 2 ]]; then
    status="warn"
    ((WARN++))
  else
    ((PASS++))
  fi

  # JSON-safe escape: prefer python3, fallback to simple escaping
  local details
  details=$(printf '%s' "$output" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))' 2>/dev/null) || \
    details="\"$(printf '%s' "$output" | sed 's/\\/\\\\/g;s/"/\\"/g;s/\t/\\t/g' | tr '\n' ' ' | head -c 500)\""
  RESULTS+=("{\"eval\":\"$name\",\"status\":\"$status\",\"details\":$details}")

  if [[ "$JSON_OUTPUT" == "false" ]]; then
    local icon="✅"
    [[ "$status" == "fail" ]] && icon="❌"
    [[ "$status" == "warn" ]] && icon="⚠️"
    echo "$icon $name: $status"
    if [[ -n "$output" && "$status" != "pass" ]]; then
      echo "   $output" | head -5
    fi
  fi
}

# Run evals
run_eval "kernel-boundary"   "$SCRIPT_DIR/check-kernel-boundary.sh"
run_eval "schema-validation" "$SCRIPT_DIR/check-schema.sh"
run_eval "agent-definitions" "$SCRIPT_DIR/check-agent-defs.sh"
run_eval "security-rules"    "$SCRIPT_DIR/check-security.sh"

# Intelligence-specific evals (only if relevant files changed or no filter)
if [[ ${#CHANGED_FILES[@]} -eq 0 ]] || echo "${CHANGED_FILES_STR}" | grep -q "INTELLIGENCE\|oip-auto"; then
  if [[ -f "$SCRIPT_DIR/check-oip-format.sh" ]]; then
    run_eval "oip-format" "$SCRIPT_DIR/check-oip-format.sh"
  fi
fi

# Output
OVERALL="pass"
[[ $FAIL -gt 0 ]] && OVERALL="fail"

if [[ "$JSON_OUTPUT" == "true" ]]; then
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  RESULTS_JSON=$(IFS=,; echo "${RESULTS[*]}")
  echo "{\"timestamp\":\"$TIMESTAMP\",\"overall\":\"$OVERALL\",\"pass\":$PASS,\"fail\":$FAIL,\"warn\":$WARN,\"results\":[$RESULTS_JSON]}"
else
  echo ""
  echo "--- Result: $OVERALL (pass=$PASS, fail=$FAIL, warn=$WARN) ---"
fi

[[ $FAIL -gt 0 ]] && exit 1
exit 0
