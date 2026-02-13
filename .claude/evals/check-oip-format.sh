#!/usr/bin/env bash
# Eval: OIP-AUTO Format Check
# Validates that OIP-AUTO proposals (in PRs or .ai/INTELLIGENCE/) have required fields.
# Required fields: trigger, impact/影響範囲, risk/リスク, changes/変更対象
#
# Exit codes: 0=pass, 1=fail, 2=warn

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
CHANGED_FILES_STR="${CHANGED_FILES_STR:-}"

ERRORS=()
WARNINGS=()
OIP_COUNT=0

check_oip_content() {
  local file="$1"
  local filename
  filename=$(basename "$file")

  # Required fields in OIP-AUTO content
  local content
  content=$(cat "$file")

  local missing=()
  # Check for required sections (Japanese or English)
  if ! echo "$content" | grep -qiE "(trigger|トリガー)"; then
    missing+=("trigger/トリガー")
  fi
  if ! echo "$content" | grep -qiE "(impact|影響範囲|影響)"; then
    missing+=("impact/影響範囲")
  fi
  if ! echo "$content" | grep -qiE "(risk|リスク)"; then
    missing+=("risk/リスク")
  fi
  if ! echo "$content" | grep -qiE "(changes|変更対象|変更ファイル)"; then
    missing+=("changes/変更対象")
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    ERRORS+=("$filename: missing required fields: ${missing[*]}")
  fi
}

# Check OIP files in .ai/INTELLIGENCE/ (if any exist)
if [[ -d "$REPO_ROOT/.ai/INTELLIGENCE/reports" ]]; then
  for report_file in "$REPO_ROOT/.ai/INTELLIGENCE/reports"/*.md; do
    [[ ! -f "$report_file" ]] && continue
    # Only check reports that contain OIP-AUTO sections
    if grep -q "OIP-AUTO" "$report_file"; then
      ((OIP_COUNT++))
      check_oip_content "$report_file"
    fi
  done
fi

# Check changed files for OIP content
if [[ -n "$CHANGED_FILES_STR" ]]; then
  for changed in $CHANGED_FILES_STR; do
    full_path="$REPO_ROOT/$changed"
    [[ ! -f "$full_path" ]] && continue
    if echo "$changed" | grep -qi "oip-auto"; then
      ((OIP_COUNT++))
      check_oip_content "$full_path"
    fi
  done
fi

# --- Output ---
if [[ $OIP_COUNT -eq 0 ]]; then
  echo "No OIP-AUTO proposals found to validate."
  exit 0
fi

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "OIP format validation failed ($OIP_COUNT proposals checked):"
  for e in "${ERRORS[@]}"; do
    echo "  ❌ $e"
  done
  exit 1
fi

echo "All $OIP_COUNT OIP-AUTO proposals valid."
exit 0
