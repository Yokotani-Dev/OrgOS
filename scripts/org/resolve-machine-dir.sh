#!/usr/bin/env bash
# Resolve an OrgOS machine-dir base name to an absolute path (new-then-legacy).
#
# Safety net for the layout migration (T-OS-497,
# .ai/DESIGN/LAYOUT_MIGRATION_COMPAT.md §3 機構2). New layout keeps machine dirs
# under .ai/_machine/<name>. Older repos keep them at .ai/<OLD> where <OLD> is the
# historical (often CamelCase) name.
#
# Resolution order:
#   1. <root>/.ai/_machine/<name>           if it exists
#   2. <root>/.ai/<legacy-alias>            if any historical alias exists
#   3. <root>/.ai/_machine/<name>           default (created with --ensure)
#
# Usage:
#   resolve-machine-dir.sh <name> [--root <repo-root>] [--ensure]
#
# Echoes the absolute path to stdout. bash macOS 3.2 compatible (no assoc arrays).

set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") <name> [--root <repo-root>] [--ensure]" >&2
  exit 2
}

# Map a new machine-dir base name to a space-separated list of historical
# legacy aliases. Source of truth: .ai/DESIGN/ORGOS_TOBE_V3.md §4.3 and
# .ai/DESIGN/LAYOUT_MIGRATION_COMPAT.md. First existing alias wins.
legacy_aliases_for() {
  case "$1" in
    events)            echo "events" ;;
    leases)            echo "leases" ;;
    codex)             echo "CODEX" ;;
    evolution)         echo "EVOLUTION" ;;
    queue)             echo "queue" ;;
    intelligence)      echo "INTELLIGENCE" ;;
    metrics)           echo "METRICS" ;;
    review)            echo "REVIEW" ;;
    sessions)          echo "sessions" ;;
    scheduler)         echo "SCHEDULER" ;;
    artifacts)         echo "ARTIFACTS artifacts" ;;
    supervisor-review) echo "SUPERVISOR_REVIEW" ;;
    learnings)         echo "LEARNED LEARNINGS" ;;
    approvals)         echo "APPROVALS" ;;
    os)                echo "OS" ;;
    backups)           echo "BACKUPS" ;;
    integrity)         echo "INTEGRITY" ;;
    *)                 echo "" ;;
  esac
}

find_repo_root() {
  # Walk up from $1 (default cwd) to the OrgOS repo root.
  local dir
  dir="$(cd "${1:-$PWD}" && pwd)"
  while :; do
    if [ -e "$dir/.git" ] || [ -d "$dir/scripts/org" ]; then
      echo "$dir"
      return 0
    fi
    if [ "$dir" = "/" ]; then
      break
    fi
    dir="$(dirname "$dir")"
  done
  # Fallback: original cwd
  (cd "${1:-$PWD}" && pwd)
}

NAME=""
ROOT=""
ENSURE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      [ $# -ge 2 ] || usage
      ROOT="$2"
      shift 2
      ;;
    --ensure)
      ENSURE=1
      shift
      ;;
    -h|--help)
      usage
      ;;
    -*)
      usage
      ;;
    *)
      if [ -z "$NAME" ]; then
        NAME="$1"
        shift
      else
        usage
      fi
      ;;
  esac
done

[ -n "$NAME" ] || usage

if [ -n "$ROOT" ]; then
  BASE="$(cd "$ROOT" && pwd)"
else
  BASE="$(find_repo_root "$PWD")"
fi

AI_DIR="$BASE/.ai"
NEW_PATH="$AI_DIR/_machine/$NAME"

RESOLVED=""
if [ -e "$NEW_PATH" ]; then
  RESOLVED="$NEW_PATH"
else
  for alias in $(legacy_aliases_for "$NAME"); do
    if [ -e "$AI_DIR/$alias" ]; then
      RESOLVED="$AI_DIR/$alias"
      break
    fi
  done
  if [ -z "$RESOLVED" ]; then
    RESOLVED="$NEW_PATH"
  fi
fi

if [ "$ENSURE" -eq 1 ]; then
  if [ "$RESOLVED" = "$NEW_PATH" ]; then
    mkdir -p "$RESOLVED"
  else
    mkdir -p "$(dirname "$RESOLVED")"
  fi
fi

echo "$RESOLVED"
