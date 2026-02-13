#!/usr/bin/env bash
# Eval: Schema Validation
# Validates that TASKS.yaml and CONTROL.yaml have the required structure.
# Not a full YAML parser — checks for required keys and basic structure.
#
# Exit codes: 0=pass, 1=fail, 2=warn

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

ERRORS=()
WARNINGS=()

# --- TASKS.yaml ---
TASKS_FILE="$REPO_ROOT/.ai/TASKS.yaml"
if [[ -f "$TASKS_FILE" ]]; then
  # Check: file starts with tasks list
  if ! grep -q "^tasks:" "$TASKS_FILE"; then
    ERRORS+=("TASKS.yaml: missing 'tasks:' root key")
  fi

  # Check: each task has required fields (id, title, status)
  TASK_COUNT=$(grep -c "^  - id:" "$TASKS_FILE" || true)
  ID_COUNT=$(grep -c "^    title:" "$TASKS_FILE" || true)
  STATUS_COUNT=$(grep -c "^    status:" "$TASKS_FILE" || true)

  if [[ "$TASK_COUNT" -gt 0 ]]; then
    if [[ "$ID_COUNT" -lt "$TASK_COUNT" ]]; then
      ERRORS+=("TASKS.yaml: some tasks missing 'title' field ($ID_COUNT/$TASK_COUNT)")
    fi
    if [[ "$STATUS_COUNT" -lt "$TASK_COUNT" ]]; then
      ERRORS+=("TASKS.yaml: some tasks missing 'status' field ($STATUS_COUNT/$TASK_COUNT)")
    fi
  fi

  # Check: valid status values
  VALID_STATUSES="queued|running|blocked|review|done|archived|pending_review"
  while IFS= read -r line; do
    status_val=$(echo "$line" | awk '{print $2}' | tr -d '"')
    if [[ -n "$status_val" ]] && ! echo "$status_val" | grep -qE "^($VALID_STATUSES)$"; then
      ERRORS+=("TASKS.yaml: invalid status value '$status_val'")
    fi
  done < <(grep "^    status:" "$TASKS_FILE")
else
  WARNINGS+=("TASKS.yaml not found (may be pre-initialization)")
fi

# --- CONTROL.yaml ---
CONTROL_FILE="$REPO_ROOT/.ai/CONTROL.yaml"
if [[ -f "$CONTROL_FILE" ]]; then
  # Required keys
  for key in "stage:" "autopilot:" "paused:" "awaiting_owner:" "main_branch:" "owner_literacy_level:"; do
    if ! grep -q "$key" "$CONTROL_FILE"; then
      ERRORS+=("CONTROL.yaml: missing required key '$key'")
    fi
  done

  # Check: valid stage
  STAGE=$(grep "^stage:" "$CONTROL_FILE" | head -1 | awk '{print $2}')
  case "$STAGE" in
    KICKOFF|REQUIREMENTS|DESIGN|IMPLEMENTATION|INTEGRATION|RELEASE) ;;
    *) ERRORS+=("CONTROL.yaml: invalid stage '$STAGE'") ;;
  esac

  # Check: boolean fields are true/false
  for bool_key in "autopilot" "paused" "awaiting_owner"; do
    VALUE=$(grep "^$bool_key:" "$CONTROL_FILE" | head -1 | awk '{print $2}')
    case "$VALUE" in
      true|false) ;;
      *) ERRORS+=("CONTROL.yaml: '$bool_key' should be true/false, got '$VALUE'") ;;
    esac
  done

  # Check: gates section exists
  if ! grep -q "^gates:" "$CONTROL_FILE"; then
    ERRORS+=("CONTROL.yaml: missing 'gates:' section")
  fi
else
  ERRORS+=("CONTROL.yaml not found")
fi

# --- Output ---
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "Schema validation failed:"
  for e in "${ERRORS[@]}"; do
    echo "  ❌ $e"
  done
  exit 1
fi

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  echo "Schema validation passed with warnings:"
  for w in "${WARNINGS[@]}"; do
    echo "  ⚠️ $w"
  done
  exit 2
fi

echo "Schema validation passed."
exit 0
