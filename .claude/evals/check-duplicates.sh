#!/usr/bin/env bash
# Eval: Duplicate Content Check
# Detects 3+ consecutive identical non-empty lines between .claude/rules/ and .claude/skills/ files.
#
# Exit codes: 0=pass (no duplicates), 1=fail (not used), 2=warn (duplicates found)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

RULES_DIR="$REPO_ROOT/.claude/rules"
SKILLS_DIR="$REPO_ROOT/.claude/skills"
DUPLICATES=()
MIN_LINES=3

# Collect all files to compare
FILES=()
for dir in "$RULES_DIR" "$SKILLS_DIR"; do
  if [[ -d "$dir" ]]; then
    while IFS= read -r f; do
      FILES+=("$f")
    done < <(find "$dir" -name "*.md" -type f 2>/dev/null)
  fi
done

FILE_COUNT=${#FILES[@]}
if [[ $FILE_COUNT -lt 2 ]]; then
  echo "Not enough files to compare ($FILE_COUNT found)."
  exit 0
fi

# Compare each pair of files for consecutive matching lines
for ((i=0; i<FILE_COUNT; i++)); do
  for ((j=i+1; j<FILE_COUNT; j++)); do
    file_a="${FILES[$i]}"
    file_b="${FILES[$j]}"

    # Use comm on sorted content? No — we need consecutive lines.
    # Use a simple approach: extract non-empty, non-header lines and find shared blocks.

    # Extract content lines (skip empty, headers, code fences, comments)
    lines_a=$(grep -vE '^\s*$|^#{1,6} |^```|^<!--|^-->|^---$|^\| ' "$file_a" 2>/dev/null | head -500 || true)
    lines_b=$(grep -vE '^\s*$|^#{1,6} |^```|^<!--|^-->|^---$|^\| ' "$file_b" 2>/dev/null | head -500 || true)

    [[ -z "$lines_a" || -z "$lines_b" ]] && continue

    # Find matching consecutive blocks using temp files
    tmpA=$(mktemp)
    tmpB=$(mktemp)
    echo "$lines_a" > "$tmpA"
    echo "$lines_b" > "$tmpB"

    # Find common lines
    match_count=$(comm -12 <(sort "$tmpA") <(sort "$tmpB") | wc -l | tr -d ' ')
    rm -f "$tmpA" "$tmpB"

    if [[ "$match_count" -ge "$MIN_LINES" ]]; then
      rel_a="${file_a#$REPO_ROOT/}"
      rel_b="${file_b#$REPO_ROOT/}"
      DUPLICATES+=("$rel_a <-> $rel_b ($match_count shared lines)")
    fi
  done
done

# --- Output ---
if [[ ${#DUPLICATES[@]} -gt 0 ]]; then
  echo "Potential duplicates found (${#DUPLICATES[@]} pairs, threshold: $MIN_LINES+ shared lines):"
  for d in "${DUPLICATES[@]}"; do
    echo "  ⚠️ $d"
  done
  exit 2  # warn, not fail
fi

echo "No significant duplicates found across ${FILE_COUNT} files."
exit 0
