#!/usr/bin/env bash
# Eval: Security Rules Check
# Verifies that critical security files exist and contain expected sections.
#
# Exit codes: 0=pass, 1=fail, 2=warn

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

ERRORS=()
WARNINGS=()

# --- security.md ---
SECURITY_FILE="$REPO_ROOT/.claude/rules/security.md"
if [[ -f "$SECURITY_FILE" ]]; then
  # Check for required sections
  for section in "OWASP" "シークレット管理" "認証" "入力"; do
    if ! grep -qi "$section" "$SECURITY_FILE"; then
      ERRORS+=("security.md: missing expected section containing '$section'")
    fi
  done
else
  ERRORS+=("security.md not found (CRITICAL: security rules missing)")
fi

# --- review-criteria.md ---
REVIEW_FILE="$REPO_ROOT/.claude/rules/review-criteria.md"
if [[ -f "$REVIEW_FILE" ]]; then
  # Check for severity levels
  for level in "CRITICAL" "HIGH" "MEDIUM" "LOW"; do
    if ! grep -q "$level" "$REVIEW_FILE"; then
      ERRORS+=("review-criteria.md: missing severity level '$level'")
    fi
  done
else
  ERRORS+=("review-criteria.md not found (CRITICAL: review criteria missing)")
fi

# --- project-flow.md ---
FLOW_FILE="$REPO_ROOT/.claude/rules/project-flow.md"
if [[ -f "$FLOW_FILE" ]]; then
  # Basic existence check
  if ! grep -q "OrgOS" "$FLOW_FILE"; then
    WARNINGS+=("project-flow.md: may not contain OrgOS flow rules")
  fi
else
  ERRORS+=("project-flow.md not found")
fi

# --- CONTROL.yaml safety flags ---
CONTROL_FILE="$REPO_ROOT/.ai/CONTROL.yaml"
if [[ -f "$CONTROL_FILE" ]]; then
  # Check that destructive ops are not enabled by default
  DESTRUCTIVE=$(grep "^allow_destructive_ops:" "$CONTROL_FILE" | head -1 | awk '{print $2}')
  if [[ "$DESTRUCTIVE" == "true" ]]; then
    WARNINGS+=("CONTROL.yaml: allow_destructive_ops is true (verify this is intentional)")
  fi
fi

# --- Output ---
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "Security rules check failed:"
  for e in "${ERRORS[@]}"; do
    echo "  ❌ $e"
  done
  exit 1
fi

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  echo "Security rules present with warnings:"
  for w in "${WARNINGS[@]}"; do
    echo "  ⚠️ $w"
  done
  exit 2
fi

echo "Security rules intact."
exit 0
