#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/authority/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/authority/principal-detect.sh [--role ROLE]
USAGE
  exit 2
}

role=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role)
      [[ $# -ge 2 ]] || usage
      role="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

if [[ -n "$role" ]]; then
  case "$role" in
    codex|codex_implementer)
      printf 'codex_implementer\n'
      ;;
    reviewer|codex_reviewer)
      printf 'codex_reviewer\n'
      ;;
    owner|manager|subagent_org_reviewer)
      printf '%s\n' "$role"
      ;;
    *)
      die "unknown role: $role"
      ;;
  esac
  exit 0
fi

if [[ -n "${CODEX_THREAD_ID:-}" ]]; then
  printf 'codex_implementer\n'
  exit 0
fi

printf 'manager\n'
