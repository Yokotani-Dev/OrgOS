#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
LEASE_DIR="$REPO_ROOT/.ai/_machine/leases"
EVENTS_PATH="${ORGOS_EVENTS_PATH:-$REPO_ROOT/.ai/EVENTS.jsonl}"

usage() {
  echo "Usage: release-lease.sh <lease_id> [--reason done|cancelled|expired]" >&2
}

emit_lease_event() {
  local event_type="$1"
  local lease_path="$2"
  local release_reason="$3"

  mkdir -p "$(dirname "$EVENTS_PATH")"
  python3 - "$EVENTS_PATH" "$event_type" "$lease_path" "$release_reason" "$(basename "$0")" <<'PY'
import json
import secrets
import sys
from datetime import datetime, timezone

events_path, event_type, lease_path, release_reason, source = sys.argv[1:6]
with open(lease_path, "r", encoding="utf-8") as handle:
    lease = json.load(handle)

now = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
payload = {
    "schema_version": "orgos.event.v1",
    "event_id": f"EV-{now.replace('-', '').replace(':', '')}-{lease.get('lease_id', 'unknown')}-{secrets.token_hex(4)}",
    "event_type": event_type,
    "type": event_type,
    "occurred_at": now,
    "source": f"scripts/org/{source}",
    "lease_id": lease.get("lease_id"),
    "task_id": lease.get("task_id"),
    "actor": lease.get("actor", {}),
    "allowed_paths": lease.get("allowed_paths", []),
    "lease_status": lease.get("status"),
    "release_reason": release_reason,
    "lease": {
        "acquired_at": lease.get("acquired_at"),
        "expires_at": lease.get("expires_at"),
        "heartbeat_at": lease.get("heartbeat_at"),
        "released_at": lease.get("released_at"),
    },
}
for key in ("worktree_path", "branch"):
    if lease.get(key):
        payload[key] = lease[key]

with open(events_path, "a", encoding="utf-8") as handle:
    json.dump(payload, handle, sort_keys=True)
    handle.write("\n")
PY
}

if [ "$#" -lt 1 ]; then
  usage
  exit 2
fi

lease_id="$1"
shift
reason="done"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --reason)
      reason="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

case "$reason" in
  done|cancelled|expired) ;;
  *)
    echo "invalid release reason: $reason" >&2
    exit 2
    ;;
esac

lease_path="$LEASE_DIR/$lease_id.json"
released_dir="$LEASE_DIR/.released"
released_path="$released_dir/$lease_id.json"

if [ ! -f "$lease_path" ]; then
  echo "lease not found: $lease_id" >&2
  exit 1
fi

mkdir -p "$released_dir"
tmp_path="$LEASE_DIR/.$lease_id.release.tmp"

python3 - "$lease_path" "$reason" <<'PY' >"$tmp_path"
import json
import sys
from datetime import datetime, timezone

lease_path, reason = sys.argv[1:3]
with open(lease_path, "r", encoding="utf-8") as handle:
    lease = json.load(handle)
lease["status"] = "released"
lease["released_at"] = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
notes = str(lease.get("notes", "") or "")
release_note = f"release_reason={reason}"
lease["notes"] = f"{notes}; {release_note}" if notes else release_note
json.dump(lease, sys.stdout, indent=2, sort_keys=True)
sys.stdout.write("\n")
PY

mv "$tmp_path" "$released_path"
rm -f "$lease_path"
emit_lease_event LeaseReleased "$released_path" "$reason"
printf '%s\n' "$released_path"
