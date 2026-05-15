#!/usr/bin/env bash
# Usage: bash scripts/org/set-kernel-mode.sh <warn|enforce|disabled>
#
# Manages .claude/state/kernel-mode.json which controls pretool_policy.py enforcement.
# - warn:     print ORGOS_POLICY_WARN, allow execution (default if file missing)
# - enforce:  print ORGOS_POLICY_DENY, exit 2 (block execution)
# - disabled: skip invariant checks entirely
#
# Refs:
# - .claude/hooks/pretool_policy.py: kernel mode reading logic
# - .ai/REVIEW/T-OS-400/external-ai-4th-response.md Q18: spec
set -euo pipefail

mode="${1:-}"

case "$mode" in
  warn|enforce|disabled) ;;
  ""|"-h"|"--help")
    echo "Usage: $0 <warn|enforce|disabled>" >&2
    exit 2
    ;;
  *)
    echo "Error: invalid mode '$mode'. Must be one of: warn|enforce|disabled" >&2
    exit 2
    ;;
esac

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
state_dir="$repo_root/.claude/state"
mode_file="$state_dir/kernel-mode.json"

mkdir -p "$state_dir"

cat > "$mode_file" <<EOF
{
  "mode": "$mode",
  "set_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "set_by": "${USER:-unknown}"
}
EOF

echo "Kernel mode set to: $mode"
echo "Wrote: $mode_file"
