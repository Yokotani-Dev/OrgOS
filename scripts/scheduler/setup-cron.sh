#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

usage() {
  cat <<'EOF'
Usage: bash scripts/scheduler/setup-cron.sh

Prints a proposed cron entry for the OrgOS scheduler. It does not modify crontab.
EOF
}

if [[ $# -gt 0 ]]; then
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
fi

cat <<EOF
# OrgOS scheduler cron proposal
#
# This script only prints the entry. Owner must install it manually with:
#   crontab -e
#
# GitHub Actions runs at 02:00 UTC. Local cron uses the machine timezone unless
# your cron implementation supports CRON_TZ. For Asia/Tokyo, 02:00 UTC is 11:00.
#
# Suggested local-time entry:
0 11 * * * cd "$REPO_ROOT" && ORGOS_SCHEDULER_TRIGGER=cron /bin/bash scripts/scheduler/run-detection.sh >> "$REPO_ROOT/.ai/SCHEDULER/cron.stdout.log" 2>> "$REPO_ROOT/.ai/SCHEDULER/cron.stderr.log"
#
# Optional UTC-style entry for cron implementations that support CRON_TZ:
CRON_TZ=UTC
0 2 * * * cd "$REPO_ROOT" && ORGOS_SCHEDULER_TRIGGER=cron /bin/bash scripts/scheduler/run-detection.sh >> "$REPO_ROOT/.ai/SCHEDULER/cron.stdout.log" 2>> "$REPO_ROOT/.ai/SCHEDULER/cron.stderr.log"
EOF
