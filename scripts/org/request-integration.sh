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
  [--allowed-paths "p1,p2,..."] \
  [--diff-patch PATH] \
  [--handoff PATH] \
  [--priority 50] \
  [--verifier-status passed|skipped] \
  [--max-diff-lines N] \
  [--allow-main]

Notes:
  --max-diff-lines defaults to 20000 (override: env ORGOS_MAX_DIFF_LINES).
  --allow-main permits a main-targeted integration (branch == main) only when
    .ai/CONTROL.yaml sets allow_main_mutation: true. ProtectedBranchNoTouch
    semantics are preserved for every other protected branch (develop, etc.).
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
allowed_paths_arg=""
allowed_paths_arg_set="0"
diff_patch=""
handoff=""
priority="50"
verifier_status="passed"
max_diff_lines="${ORGOS_MAX_DIFF_LINES:-20000}"
allow_main="0"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --task-id) task_id=${2:-}; shift 2 ;;
    --worktree-path) worktree_path=${2:-}; shift 2 ;;
    --branch) branch=${2:-}; shift 2 ;;
    --base-branch) base_branch=${2:-}; shift 2 ;;
    --artifact-manifest) artifact_manifest=${2:-}; shift 2 ;;
    --commit-message) commit_message=${2:-}; shift 2 ;;
    --allowed-paths) allowed_paths_arg=${2:-}; allowed_paths_arg_set="1"; shift 2 ;;
    --diff-patch) diff_patch=${2:-}; shift 2 ;;
    --handoff) handoff=${2:-}; shift 2 ;;
    --priority) priority=${2:-}; shift 2 ;;
    --verifier-status) verifier_status=${2:-}; shift 2 ;;
    --max-diff-lines) max_diff_lines=${2:-}; shift 2 ;;
    --allow-main) allow_main="1"; shift ;;
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

# Returns 0 (true) when .ai/CONTROL.yaml grants allow_main_mutation: true.
control_allows_main_mutation() {
  local repo_root="$1"
  python3 - "$repo_root" <<'PY'
import sys
from pathlib import Path

control = Path(sys.argv[1]) / ".ai" / "CONTROL.yaml"
allowed = False
try:
    text = control.read_text(encoding="utf-8")
except OSError:
    raise SystemExit(1)

value = None
try:
    import yaml  # type: ignore

    data = yaml.safe_load(text) or {}
    if isinstance(data, dict):
        value = data.get("allow_main_mutation")
except Exception:
    value = None

if value is None:
    # Fallback: top-level "allow_main_mutation: <bool>" line scan (no yaml dependency).
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("#"):
            continue
        if stripped.replace(" ", "").lower().startswith("allow_main_mutation:"):
            raw = stripped.split(":", 1)[1].strip().strip('"').strip("'").lower()
            value = raw in {"true", "yes", "1", "on"}
            break

allowed = value is True
raise SystemExit(0 if allowed else 1)
PY
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

# Main integration mode: when --allow-main is passed AND CONTROL.yaml grants
# allow_main_mutation, a main-targeted integration (branch == main) is sanctioned
# without the time-boxed IntegratorOnlyCommit downgrade (precedent OS-MUTATION-001..005).
# ProtectedBranchNoTouch semantics are preserved for every OTHER protected branch.
main_integration="0"
if [[ "$branch" == "main" ]]; then
  if [ "$allow_main" != "1" ]; then
    echo "protected branch is not a task branch: $branch (pass --allow-main for a sanctioned main integration)" >&2
    exit 2
  fi
  if ! control_allows_main_mutation "$REPO_ROOT"; then
    echo "main integration denied: CONTROL.yaml allow_main_mutation must be true" >&2
    exit 2
  fi
  main_integration="1"
elif [[ "$branch" == "develop" ]]; then
  echo "protected branch is not a task branch: $branch" >&2
  exit 2
fi

if [ "$main_integration" != "1" ] && [[ ! "$branch" =~ ^task/${task_id}-.+ ]]; then
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

if ! [[ "$max_diff_lines" =~ ^[0-9]+$ ]] || [ "$max_diff_lines" -lt 1 ]; then
  echo "max diff lines must be a positive integer (got: $max_diff_lines); set --max-diff-lines or ORGOS_MAX_DIFF_LINES" >&2
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

queue_dir="$REPO_ROOT/.ai/_machine/queue/integration"
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
  "$allowed_paths_arg_set" "$allowed_paths_arg" "$priority" "$verifier_status" \
  "$max_diff_lines" "$main_integration" >"$tmp_path" <<'PY'
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
    allowed_paths_arg_set,
    allowed_paths_arg,
    priority,
    verifier_status,
    max_diff_lines,
    main_integration,
) = sys.argv[1:18]

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

def parse_comma(value: str) -> list[str]:
    return [part.strip() for part in value.split(",") if part.strip()]


def parse_dt(value: object):
    if not isinstance(value, str) or not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def find_active_lease_for_task(task_id: str):
    leases_dir = root / ".ai" / "_machine" / "leases"
    if not leases_dir.is_dir():
        return None
    now = datetime.now(timezone.utc)
    for path in sorted(leases_dir.glob("*.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            continue
        if data.get("task_id") != task_id or data.get("status") != "active":
            continue
        expires_at = parse_dt(data.get("expires_at"))
        if expires_at is not None and expires_at <= now:
            continue
        return data
    return None

try:
    base_commit = git("rev-parse", base_branch)
except subprocess.CalledProcessError:
    base_commit = git("rev-parse", "HEAD")
expected_head = git("rev-parse", "HEAD")

if allowed_paths_arg_set == "1":
    allowed_paths = parse_comma(allowed_paths_arg)
else:
    lease = find_active_lease_for_task(task_id)
    if lease is None:
        print(
            "allowed_paths required: provide --allowed-paths or have an active lease for this task",
            file=sys.stderr,
        )
        raise SystemExit(2)
    allowed_paths = [str(path) for path in lease.get("allowed_paths", [])]

if not allowed_paths:
    print("allowed_paths cannot be empty", file=sys.stderr)
    raise SystemExit(2)

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
        "diff_budget": {"max_files": max(10, len(allowed_paths) * 5), "max_lines": int(max_diff_lines)},
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
        "main_integration": main_integration == "1",
    },
    "attempts": {"count": 0, "max": 3, "last_attempt_at": None, "last_error": None},
    "retention": {"keep_until": keep_until},
}

json.dump(item, sys.stdout, indent=2, sort_keys=True)
sys.stdout.write("\n")
PY

mv "$tmp_path" "$queue_path"
printf '%s\n' "$queue_path"
