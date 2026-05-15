#!/usr/bin/env bash
# Usage:
#   bash scripts/org/set-kernel-mode.sh <warn|enforce|disabled>
#   bash scripts/org/set-kernel-mode.sh --invariant IntegratorOnlyCommit enforce
#   bash scripts/org/set-kernel-mode.sh --list
#   bash scripts/org/set-kernel-mode.sh --reset
#
# Manages .claude/state/kernel-mode.json which controls pretool_policy.py enforcement.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  scripts/org/set-kernel-mode.sh <warn|enforce|disabled>
  scripts/org/set-kernel-mode.sh --invariant <InvariantId> <warn|enforce|disabled>
  scripts/org/set-kernel-mode.sh --list
  scripts/org/set-kernel-mode.sh --reset
EOF
}

is_mode() {
  case "${1:-}" in
    warn|enforce|disabled) return 0 ;;
    *) return 1 ;;
  esac
}

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
state_dir="$repo_root/.claude/state"
mode_file="$state_dir/kernel-mode.json"

mkdir -p "$state_dir"

action=""
mode=""
invariant=""

case "${1:-}" in
  --list)
    [ "$#" -eq 1 ] || { usage; exit 2; }
    action="list"
    ;;
  --reset)
    [ "$#" -eq 1 ] || { usage; exit 2; }
    action="reset"
    ;;
  --invariant)
    [ "$#" -eq 3 ] || { usage; exit 2; }
    invariant="$2"
    mode="$3"
    is_mode "$mode" || { echo "Error: invalid mode '$mode'. Must be one of: warn|enforce|disabled" >&2; exit 2; }
    action="set_invariant"
    ;;
  warn|enforce|disabled)
    [ "$#" -eq 1 ] || { usage; exit 2; }
    mode="$1"
    action="set_global"
    ;;
  ""|"-h"|"--help")
    usage
    exit 2
    ;;
  *)
    echo "Error: invalid argument '$1'" >&2
    usage
    exit 2
    ;;
esac

python3 - "$mode_file" "$action" "$mode" "$invariant" "${USER:-unknown}" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

mode_file = Path(sys.argv[1])
action = sys.argv[2]
mode = sys.argv[3]
target_invariant = sys.argv[4]
user = sys.argv[5]

VALID_MODES = {"warn", "enforce", "disabled"}
INVARIANTS = [
    "IntegratorOnlyCommit",
    "PerTaskWorktree",
    "ProtectedBranchNoTouch",
    "LeaseBeforeWrite",
    "StateMutationViaOrgTool",
    "DurableArtifactBeforeCleanup",
    "OwnerApprovalForIrreversibleOps",
    "DangerousShell",
    "KernelSelfModification",
    "IntegratorIsScriptNotAgent",
]


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def normalize_mode(value: object, default: str = "warn") -> str:
    value = str(value or "").strip()
    return value if value in VALID_MODES else default


def load_payload() -> dict:
    try:
        payload = json.loads(mode_file.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        payload = {}

    if not isinstance(payload, dict):
        payload = {}

    schema_version = str(payload.get("schema_version", "") or "")
    if schema_version in ("", "orgos.kernel-mode.v1", "v1"):
        default = normalize_mode(payload.get("mode"))
        invariants = {invariant: default for invariant in INVARIANTS}
    else:
        default = normalize_mode(payload.get("default"))
        raw_invariants = payload.get("invariants", {})
        if not isinstance(raw_invariants, dict):
            raw_invariants = {}
        invariants = {
            invariant: normalize_mode(raw_invariants.get(invariant), default)
            for invariant in INVARIANTS
        }

    return {
        "schema_version": "orgos.kernel-mode.v2",
        "default": default,
        "invariants": invariants,
        "set_at": str(payload.get("set_at", "") or utc_now()),
        "set_by": str(payload.get("set_by", "") or user),
        "notes": str(payload.get("notes", "") or ""),
    }


def write_payload(payload: dict) -> None:
    payload["set_at"] = utc_now()
    payload["set_by"] = user
    tmp_path = mode_file.with_suffix(mode_file.suffix + ".tmp")
    tmp_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    os.replace(tmp_path, mode_file)


payload = load_payload()

if action == "list":
    print(f"default: {payload['default']}")
    for invariant, invariant_mode in payload["invariants"].items():
        print(f"{invariant}: {invariant_mode}")
    sys.exit(0)

if action == "reset":
    payload["default"] = "warn"
    payload["invariants"] = {invariant: "warn" for invariant in INVARIANTS}
    payload["notes"] = "Reset by set-kernel-mode.sh --reset."
    write_payload(payload)
    print(f"Kernel modes reset to warn: {mode_file}")
    sys.exit(0)

if action == "set_global":
    payload["default"] = mode
    payload["invariants"] = {invariant: mode for invariant in INVARIANTS}
    payload["notes"] = f"Global compatibility mode set to {mode}."
    write_payload(payload)
    print(f"Kernel modes set to: {mode}")
    print(f"Wrote: {mode_file}")
    sys.exit(0)

if action == "set_invariant":
    if target_invariant not in INVARIANTS:
        print(f"Error: unknown invariant '{target_invariant}'", file=sys.stderr)
        print("Known invariants:", file=sys.stderr)
        for invariant in INVARIANTS:
            print(f"  {invariant}", file=sys.stderr)
        sys.exit(2)
    payload["invariants"][target_invariant] = mode
    payload["notes"] = f"{target_invariant} set to {mode}."
    write_payload(payload)
    print(f"Kernel invariant mode set: {target_invariant}={mode}")
    print(f"Wrote: {mode_file}")
    sys.exit(0)

print(f"Error: unknown action '{action}'", file=sys.stderr)
sys.exit(2)
PY
