#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: request-integration.sh \
  --task-id T-XXX \
  --worktree-path PATH \
  --branch task/T-XXX-slug \
  --base-branch main \
  --artifact-manifest PATH \
  --commit-message MSG \
  [--diff-patch PATH] \
  [--handoff PATH] \
  [--priority 50] \
  [--verifier-status passed|skipped]
EOF
}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

task_id=""
worktree_path=""
branch=""
base_branch=""
artifact_manifest=""
commit_message=""
diff_patch=""
handoff=""
priority="50"
verifier_status="passed"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --task-id) task_id=${2:-}; shift 2 ;;
    --worktree-path) worktree_path=${2:-}; shift 2 ;;
    --branch) branch=${2:-}; shift 2 ;;
    --base-branch) base_branch=${2:-}; shift 2 ;;
    --artifact-manifest) artifact_manifest=${2:-}; shift 2 ;;
    --commit-message) commit_message=${2:-}; shift 2 ;;
    --diff-patch) diff_patch=${2:-}; shift 2 ;;
    --handoff) handoff=${2:-}; shift 2 ;;
    --priority) priority=${2:-}; shift 2 ;;
    --verifier-status) verifier_status=${2:-}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

require() {
  local value="$1"
  local name="$2"
  if [ -z "$value" ]; then
    echo "missing required argument: $name" >&2
    usage
    exit 2
  fi
}

require "$task_id" "--task-id"
require "$worktree_path" "--worktree-path"
require "$branch" "--branch"
require "$base_branch" "--base-branch"
require "$artifact_manifest" "--artifact-manifest"
require "$commit_message" "--commit-message"

if [[ ! "$task_id" =~ ^T-[A-Z0-9]+-[A-Z0-9-]+$ ]]; then
  echo "invalid task_id: $task_id" >&2
  exit 2
fi

if [[ "$branch" == "main" || "$branch" == "develop" ]]; then
  echo "protected branch is not a task branch: $branch" >&2
  exit 2
fi

if [[ ! "$branch" =~ ^task/${task_id}-.+ ]]; then
  echo "branch must match task/<task_id>-...: $branch" >&2
  exit 2
fi

if [[ ! "$verifier_status" =~ ^(passed|skipped)$ ]]; then
  echo "verifier status must be passed or skipped: $verifier_status" >&2
  exit 2
fi

if ! [[ "$priority" =~ ^[0-9]+$ ]] || [ "$priority" -gt 100 ]; then
  echo "priority must be an integer from 0 to 100" >&2
  exit 2
fi

python3 - "$artifact_manifest" "$worktree_path" <<'PY'
import json
import sys
from pathlib import Path

manifest = Path(sys.argv[1])
worktree = Path(sys.argv[2])
if not manifest.is_file():
    print(f"artifact manifest missing: {manifest}", file=sys.stderr)
    raise SystemExit(2)
try:
    with manifest.open("r", encoding="utf-8") as handle:
        json.load(handle)
except Exception as exc:
    print(f"artifact manifest is not valid JSON: {exc}", file=sys.stderr)
    raise SystemExit(2)
if not worktree.is_dir():
    print(f"worktree path missing: {worktree}", file=sys.stderr)
    raise SystemExit(2)
PY

queue_dir="$REPO_ROOT/.ai/queue/integration"
pending_dir="$queue_dir/pending"
mkdir -p "$pending_dir"
queue_path="$pending_dir/$task_id.json"
tmp_path="$queue_path.tmp"

if [ -e "$queue_path" ]; then
  echo "pending integration item already exists for $task_id: $queue_path" >&2
  exit 3
fi

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
random_hex=$(python3 - <<'PY'
import secrets
print(secrets.token_hex(4))
PY
)
item_id="IQ-$timestamp-$task_id-$random_hex"

python3 - "$REPO_ROOT" "$task_id" "$item_id" "$created_at" "$worktree_path" "$branch" \
  "$base_branch" "$artifact_manifest" "$commit_message" "$diff_patch" "$handoff" \
  "$priority" "$verifier_status" >"$tmp_path" <<'PY'
import json
import os
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

(
    repo_root,
    task_id,
    item_id,
    created_at,
    worktree_path,
    branch,
    base_branch,
    artifact_manifest,
    commit_message,
    diff_patch,
    handoff,
    priority,
    verifier_status,
) = sys.argv[1:14]

root = Path(repo_root)
worktree = Path(worktree_path)
manifest = Path(artifact_manifest)

def git(*args: str) -> str:
    return subprocess.check_output(["git", "-C", str(worktree), *args], text=True).strip()

def repo_relative(path: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return str(path)

def status_paths() -> list[str]:
    output = subprocess.check_output(
        ["git", "-C", str(worktree), "status", "--porcelain"],
        text=True,
    )
    paths: list[str] = []
    for line in output.splitlines():
        if len(line) < 4:
            continue
        path = line[3:]
        if " -> " in path:
            path = path.split(" -> ", 1)[1]
        paths.append(path)
    return sorted(set(paths))

try:
    base_commit = git("rev-parse", base_branch)
except subprocess.CalledProcessError:
    base_commit = git("rev-parse", "HEAD")
expected_head = git("rev-parse", "HEAD")

allowed_paths = status_paths() or ["**"]
keep_until = (datetime.now(timezone.utc) + timedelta(days=90)).isoformat(timespec="seconds").replace("+00:00", "Z")
passed_at = created_at if verifier_status == "passed" else None

item = {
    "schema_version": "orgos.integration_queue.v1",
    "item_id": item_id,
    "task_id": task_id,
    "project_id": os.environ.get("ORGOS_PROJECT_ID", "orgos"),
    "status": "pending",
    "created_at": created_at,
    "created_by": {
        "role": os.environ.get("ORGOS_ACTOR_ROLE", "manager"),
        "id": os.environ.get("ORGOS_ACTOR_ID", "request-integration.sh"),
        "session_id": os.environ.get("ORGOS_SESSION_ID", ""),
    },
    "priority": int(priority),
    "dependencies": {"tasks": [], "queue_items": []},
    "worktree": {
        "path": str(worktree),
        "branch": branch,
        "base_branch": base_branch,
        "base_commit": base_commit,
        "expected_head": expected_head,
    },
    "scope": {
        "allowed_paths": allowed_paths,
        "prohibited_paths": [],
        "diff_budget": {"max_files": max(1, len(allowed_paths) + 20), "max_lines": 5000},
    },
    "artifacts": {
        "artifact_manifest": repo_relative(manifest),
        "diff_patch": repo_relative(Path(diff_patch)) if diff_patch else "",
        "handoff": repo_relative(Path(handoff)) if handoff else "",
    },
    "verification": {
        "required": verifier_status != "skipped",
        "status": verifier_status,
        "commands": [],
        "artifacts": [],
        "passed_at": passed_at,
    },
    "approvals": {"plan_id": "", "approval_id": "", "approval_hash": ""},
    "commit": {
        "target_branch": base_branch,
        "message": commit_message,
        "author_name": "OrgOS Integrator",
        "author_email": "orgos-integrator@local",
        "trailers": {"OrgOS-Task": task_id},
    },
    "attempts": {"count": 0, "max": 3, "last_attempt_at": None, "last_error": None},
    "retention": {"keep_until": keep_until},
}

json.dump(item, sys.stdout, indent=2, sort_keys=True)
sys.stdout.write("\n")
PY

mv "$tmp_path" "$queue_path"
printf '%s\n' "$queue_path"
