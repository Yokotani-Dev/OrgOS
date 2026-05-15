#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
LEASE_DIR="$REPO_ROOT/.ai/leases"

usage() {
  echo "Usage: release-lease.sh <lease_id> [--reason done|cancelled|expired]" >&2
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
printf '%s\n' "$released_path"
