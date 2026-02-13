#!/usr/bin/env bash
# Eval: Kernel Boundary Check
# Verifies that changed files do not include Kernel-protected files.
# Used by OIP-AUTO auto-approve to reject Level 1 changes that touch Kernel.
#
# Exit codes: 0=pass, 1=fail, 2=warn

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
KERNEL_LIST="$SCRIPT_DIR/KERNEL_FILES"
CHANGED_FILES_STR="${CHANGED_FILES_STR:-}"

# If no changed files provided, this eval is informational only
if [[ -z "$CHANGED_FILES_STR" ]]; then
  echo "No changed files specified. Kernel boundary check skipped (informational)."
  exit 0
fi

if [[ ! -f "$KERNEL_LIST" ]]; then
  echo "KERNEL_FILES not found at $KERNEL_LIST"
  exit 1
fi

# Read kernel files (skip comments and empty lines)
KERNEL_FILES=()
while IFS= read -r line; do
  line=$(echo "$line" | sed 's/#.*//;s/^[[:space:]]*//;s/[[:space:]]*$//')
  [[ -z "$line" ]] && continue
  KERNEL_FILES+=("$line")
done < "$KERNEL_LIST"

# Check each changed file against Kernel list
# Matches: exact path or changed file is a parent directory of a Kernel file
VIOLATIONS=()
for changed in $CHANGED_FILES_STR; do
  # Strip trailing slash for directory-style paths
  changed_clean="${changed%/}"
  for kernel in "${KERNEL_FILES[@]}"; do
    if [[ "$changed_clean" == "$kernel" ]] || [[ "$kernel" == "$changed_clean"/* ]]; then
      VIOLATIONS+=("$kernel (matched by: $changed)")
    fi
  done
done

if [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
  echo "KERNEL VIOLATION: The following protected files were modified:"
  for v in "${VIOLATIONS[@]}"; do
    echo "  - $v"
  done
  echo "These files require Level 3 (Owner explicit) approval."
  exit 1
fi

echo "No Kernel files modified."
exit 0
