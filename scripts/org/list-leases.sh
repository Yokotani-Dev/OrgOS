#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
LEASE_DIR="$REPO_ROOT/.ai/_machine/leases"

task_filter=""
actor_filter=""
include_expired=0

usage() {
  echo "Usage: list-leases.sh [--task-id T-XXX] [--actor-role ROLE] [--include-expired]" >&2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --task-id)
      task_filter="${2:-}"
      shift 2
      ;;
    --actor-role)
      actor_filter="${2:-}"
      shift 2
      ;;
    --include-expired)
      include_expired=1
      shift
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

mkdir -p "$LEASE_DIR"

python3 - "$LEASE_DIR" "$task_filter" "$actor_filter" "$include_expired" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

lease_dir = Path(sys.argv[1])
task_filter = sys.argv[2]
actor_filter = sys.argv[3]
include_expired = sys.argv[4] == "1"
now = datetime.now(timezone.utc)


def parse_dt(value: str):
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None


def fmt_age(acquired_at: str) -> str:
    parsed = parse_dt(acquired_at)
    if parsed is None:
        return "unknown"
    seconds = max(0, int((now - parsed).total_seconds()))
    if seconds < 60:
        return f"{seconds}s"
    minutes = seconds // 60
    if minutes < 60:
        return f"{minutes}m"
    return f"{minutes // 60}h{minutes % 60}m"


rows = []
for path in sorted(lease_dir.glob("*.json")):
    try:
        lease = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        continue

    status = str(lease.get("status", ""))
    expires_at = parse_dt(str(lease.get("expires_at", "")))
    if status == "active" and expires_at is not None and expires_at <= now:
        lease["status"] = "expired"
        status = "expired"
        tmp_path = path.with_name(f".{path.stem}.expire.tmp")
        tmp_path.write_text(json.dumps(lease, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        tmp_path.replace(path)

    actor = lease.get("actor", {}) if isinstance(lease.get("actor"), dict) else {}
    if task_filter and lease.get("task_id") != task_filter:
        continue
    if actor_filter and actor.get("role") != actor_filter:
        continue
    if status != "active" and not (include_expired and status == "expired"):
        continue
    rows.append(
        (
            str(lease.get("lease_id", path.stem)),
            str(lease.get("task_id", "")),
            f"{actor.get('role', '')}:{actor.get('id', '')}",
            ",".join(str(p) for p in lease.get("allowed_paths", [])),
            fmt_age(str(lease.get("acquired_at", ""))),
            status,
        )
    )

print("lease_id\ttask_id\tactor\tpaths\tage\tstatus")
for row in rows:
    print("\t".join(row))
PY
