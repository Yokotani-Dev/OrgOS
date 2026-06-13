#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
LEASE_DIR="$REPO_ROOT/.ai/_machine/leases"
EVENTS_PATH="${ORGOS_EVENTS_PATH:-$REPO_ROOT/.ai/EVENTS.jsonl}"

task_id=""
actor_role=""
actor_id=""
allowed_paths=""
worktree_path=""
branch=""
ttl_seconds="1800"

usage() {
  cat >&2 <<'EOF'
Usage: acquire-lease.sh --task-id T-XXX --actor-role codex|manager|subagent|integrator|owner --actor-id ID --allowed-paths "path1,path2" [--worktree-path PATH] [--branch NAME] [--ttl-seconds 1800]
EOF
}

emit_lease_event() {
  local event_type="$1"
  local lease_path="$2"

  mkdir -p "$(dirname "$EVENTS_PATH")"
  python3 - "$EVENTS_PATH" "$event_type" "$lease_path" "$(basename "$0")" <<'PY'
import json
import secrets
import sys
from datetime import datetime, timezone

events_path, event_type, lease_path, source = sys.argv[1:5]
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
    "lease": {
        "acquired_at": lease.get("acquired_at"),
        "expires_at": lease.get("expires_at"),
        "heartbeat_at": lease.get("heartbeat_at"),
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

while [ "$#" -gt 0 ]; do
  case "$1" in
    --task-id)
      task_id="${2:-}"
      shift 2
      ;;
    --actor-role)
      actor_role="${2:-}"
      shift 2
      ;;
    --actor-id)
      actor_id="${2:-}"
      shift 2
      ;;
    --allowed-paths)
      allowed_paths="${2:-}"
      shift 2
      ;;
    --worktree-path)
      worktree_path="${2:-}"
      shift 2
      ;;
    --branch)
      branch="${2:-}"
      shift 2
      ;;
    --ttl-seconds)
      ttl_seconds="${2:-}"
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

if [ -z "$task_id" ] || [ -z "$actor_role" ] || [ -z "$actor_id" ] || [ -z "$allowed_paths" ]; then
  usage
  exit 2
fi

case "$actor_role" in
  manager|codex|subagent|integrator|owner) ;;
  *)
    echo "invalid actor role: $actor_role" >&2
    exit 2
    ;;
esac

case "$ttl_seconds" in
  ''|*[!0-9]*)
    echo "ttl-seconds must be a positive integer" >&2
    exit 2
    ;;
esac

if [ "$ttl_seconds" -le 0 ]; then
  echo "ttl-seconds must be greater than zero" >&2
  exit 2
fi

mkdir -p "$LEASE_DIR"

python3 - "$LEASE_DIR" "$allowed_paths" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

lease_dir = Path(sys.argv[1])
requested = [p.strip() for p in sys.argv[2].split(",") if p.strip()]
if not requested:
    print("allowed-paths must contain at least one path", file=sys.stderr)
    raise SystemExit(2)


def norm(path: str) -> str:
    value = path.strip().replace("\\", "/")
    while value.startswith("./"):
        value = value[2:]
    value = value.strip("/")
    return value


def path_covers(scope: str, target: str) -> bool:
    scope = norm(scope)
    target = norm(target)
    if not scope:
        return True
    return target == scope or target.startswith(scope.rstrip("/") + "/") or scope.startswith(target.rstrip("/") + "/")


def parse_dt(value: str):
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None


now = datetime.now(timezone.utc)
conflicts = []
for path in lease_dir.glob("*.json"):
    try:
        lease = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        continue
    if lease.get("status") != "active":
        continue
    expires_at = parse_dt(str(lease.get("expires_at", "")))
    if expires_at is not None and expires_at <= now:
        continue
    existing_paths = [str(p) for p in lease.get("allowed_paths", [])]
    for requested_path in requested:
        for existing_path in existing_paths:
            if path_covers(existing_path, requested_path):
                conflicts.append(
                    f"{lease.get('lease_id', path.stem)} covers {existing_path}; requested {requested_path}"
                )

if conflicts:
    print("lease conflict detected:", file=sys.stderr)
    for conflict in conflicts:
        print(f"  {conflict}", file=sys.stderr)
    raise SystemExit(3)
PY

timestamp=$(date -u +"%Y%m%dT%H%M%SZ")
safe_task_id=$(printf '%s' "$task_id" | sed 's/[^A-Za-z0-9._-]/_/g')
suffix=$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')
lease_id="LS-${timestamp}-${safe_task_id}-${suffix}"
tmp_path="$LEASE_DIR/.${lease_id}.tmp"
lease_path="$LEASE_DIR/${lease_id}.json"

python3 - "$lease_path" "$task_id" "$actor_role" "$actor_id" "$allowed_paths" "$worktree_path" "$branch" "$ttl_seconds" "$lease_id" <<'PY' >"$tmp_path"
import json
import os
import sys
from datetime import datetime, timedelta, timezone

_, task_id, actor_role, actor_id, allowed_paths, worktree_path, branch, ttl_seconds, lease_id = sys.argv[1:10]
now = datetime.now(timezone.utc)
paths = [p.strip() for p in allowed_paths.split(",") if p.strip()]
payload = {
    "schema_version": "orgos.lease.v1",
    "lease_id": lease_id,
    "task_id": task_id,
    "actor": {
        "role": actor_role,
        "id": actor_id,
    },
    "allowed_paths": paths,
    "status": "active",
    "acquired_at": now.isoformat(timespec="seconds").replace("+00:00", "Z"),
    "heartbeat_at": now.isoformat(timespec="seconds").replace("+00:00", "Z"),
    "expires_at": (now + timedelta(seconds=int(ttl_seconds))).isoformat(timespec="seconds").replace("+00:00", "Z"),
}
session_id = os.environ.get("ORGOS_SESSION_ID") or os.environ.get("CODEX_SESSION_ID") or os.environ.get("CLAUDE_SESSION_ID")
if session_id:
    payload["actor"]["session_id"] = session_id
if worktree_path:
    payload["worktree_path"] = worktree_path
if branch:
    payload["branch"] = branch
json.dump(payload, sys.stdout, indent=2, sort_keys=True)
sys.stdout.write("\n")
PY

mv "$tmp_path" "$lease_path"
emit_lease_event LeaseAcquired "$lease_path"
printf '%s\n' "$lease_id"
