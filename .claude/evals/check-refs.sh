#!/usr/bin/env bash
# Eval: Reference Path Check
# Validates that markdown links [text](path) and reference paths in .claude/ files
# point to existing files.
#
# Exit codes: 0=pass, 1=fail, 2=warn

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

BROKEN=()
CHECKED=0

# Extract markdown links from .claude/ files
while IFS= read -r file; do
  [[ ! -f "$file" ]] && continue

  # Extract [text](path) patterns — skip URLs (http/https/mailto)
  while IFS= read -r match; do
    # Extract the path part from [text](path)
    path=$(echo "$match" | sed -n 's/.*](\([^)]*\)).*/\1/p')
    [[ -z "$path" ]] && continue

    # Skip URLs, anchors-only, and generic placeholders
    [[ "$path" =~ ^https?:// ]] && continue
    [[ "$path" =~ ^mailto: ]] && continue
    [[ "$path" =~ ^# ]] && continue
    # Skip single-word lowercase placeholders (e.g. "path", "URL", "file")
    [[ "$path" =~ ^[a-zA-Z_]+$ && ! "$path" =~ \. && ! "$path" =~ / ]] && continue
    # Skip template variables like <TASK_ID>, <project-id>
    [[ "$path" =~ ^\< ]] && continue

    # Strip anchor fragments
    path_no_anchor="${path%%#*}"
    [[ -z "$path_no_anchor" ]] && continue

    ((CHECKED++))

    # Resolve relative to the file's directory
    file_dir=$(dirname "$file")
    resolved="$file_dir/$path_no_anchor"

    if [[ ! -e "$resolved" ]]; then
      # Also try from repo root
      if [[ ! -e "$REPO_ROOT/$path_no_anchor" ]]; then
        rel_file="${file#$REPO_ROOT/}"
        BROKEN+=("$rel_file -> $path")
      fi
    fi
  done < <(grep -oE '\[[^]]*\]\([^)]+\)' "$file" 2>/dev/null || true)
done < <(find "$REPO_ROOT/.claude" -name "*.md" -type f 2>/dev/null)

# --- Output ---
if [[ ${#BROKEN[@]} -gt 0 ]]; then
  echo "Broken references found (${#BROKEN[@]}/$CHECKED checked):"
  for b in "${BROKEN[@]}"; do
    echo "  ❌ $b"
  done
  exit 1
fi

echo "All $CHECKED references valid."
exit 0
