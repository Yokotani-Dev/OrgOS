#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: integrator-commit.sh --task-id T-XXX [--queue-item PATH]
       integrator-commit.sh T-XXX [--queue-item PATH]
EOF
}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
VERIFIER="$REPO_ROOT/scripts/org/verify-artifact-manifest.py"

task_id=""
queue_item=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --task-id) task_id=${2:-}; shift 2 ;;
    --queue-item) queue_item=${2:-}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -* ) echo "unknown argument: $1" >&2; usage; exit 2 ;;
    * )
      if [ -z "$task_id" ]; then
        task_id=$1
        shift
      else
        echo "unexpected argument: $1" >&2
        usage
        exit 2
      fi
      ;;
  esac
done

if [ -z "$task_id" ]; then
  echo "missing --task-id" >&2
  usage
  exit 2
fi

if [[ ! "$task_id" =~ ^T-[A-Z0-9]+-[A-Z0-9-]+$ ]]; then
  echo "invalid task_id: $task_id" >&2
  exit 2
fi

queue_root="$REPO_ROOT/.ai/queue/integration"
pending_dir="$queue_root/pending"
processing_dir="$queue_root/processing"
failed_dir="$queue_root/failed"
done_dir="$queue_root/done"

mkdir -p "$pending_dir" "$processing_dir" "$failed_dir" "$done_dir" "$REPO_ROOT/.claude/state"

if [ -z "$queue_item" ]; then
  queue_item="$pending_dir/$task_id.json"
fi

if [ ! -f "$queue_item" ]; then
  echo "queue item missing: $queue_item" >&2
  exit 2
fi

lock_file="$REPO_ROOT/.claude/state/git.lock"
lock_dir="$lock_file.d"
if ! mkdir "$lock_dir" 2>/dev/null; then
  echo "git lock is held: $lock_file" >&2
  exit 4
fi
printf 'pid=%s task_id=%s\n' "$$" "$task_id" >"$lock_file"
trap 'rm -rf "$lock_dir" "$lock_file"' EXIT

processing_path="$processing_dir/$task_id.json"
if [ -e "$processing_path" ]; then
  echo "processing queue item already exists: $processing_path" >&2
  exit 3
fi
mv "$queue_item" "$processing_path"

fail_processing() {
  local message="$1"
  local failed_path="$failed_dir/$task_id.$(date -u +%Y%m%dT%H%M%SZ).json"
  mkdir -p "$failed_dir"
  python3 - "$processing_path" "$message" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

path = Path(sys.argv[1])
message = sys.argv[2]
with path.open("r", encoding="utf-8") as handle:
    data = json.load(handle)
attempts = data.setdefault("attempts", {})
attempts["count"] = int(attempts.get("count") or 0) + 1
attempts["last_attempt_at"] = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
attempts["last_error"] = message
data["status"] = "failed"
with path.open("w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
  mv "$processing_path" "$failed_path"
  echo "$message" >&2
  echo "failed queue item: $failed_path" >&2
  exit 1
}

item_values_path=$(mktemp "${TMPDIR:-/tmp}/orgos-integrator-item.XXXXXX")
python3 - "$REPO_ROOT" "$processing_path" >"$item_values_path" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
path = Path(sys.argv[2])
try:
    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
except Exception as exc:
    print(f"ERROR:failed to parse queue item: {exc}")
    raise SystemExit(0)

def resolve(raw: str) -> str:
    value = str(raw or "")
    if not value:
        return ""
    candidate = Path(value)
    return str(candidate if candidate.is_absolute() else root / candidate)

required = [
    "schema_version", "item_id", "task_id", "status", "worktree", "scope",
    "artifacts", "verification", "commit", "attempts", "dependencies",
]
missing = [key for key in required if key not in data]
if missing:
    print(f"ERROR:missing queue fields: {', '.join(missing)}")
    raise SystemExit(0)
if data.get("schema_version") != "orgos.integration_queue.v1":
    print("ERROR:schema_version must be orgos.integration_queue.v1")
    raise SystemExit(0)
if data.get("status") != "pending":
    print(f"ERROR:queue item status must be pending, got {data.get('status')}")
    raise SystemExit(0)

worktree = data.get("worktree") or {}
artifacts = data.get("artifacts") or {}
verification = data.get("verification") or {}
commit = data.get("commit") or {}
scope = data.get("scope") or {}

print("OK")
print(resolve(worktree.get("path", "")))
print(str(worktree.get("branch", "")))
print(str(worktree.get("base_branch", "")))
print(str(worktree.get("base_commit", "")))
print(str(worktree.get("expected_head", "")))
print(resolve(artifacts.get("artifact_manifest", "")))
print("true" if verification.get("required") is True else "false")
print(str(verification.get("status", "")))
print(str(commit.get("message", "")))
print(str(commit.get("author_name", "OrgOS Integrator")))
print(str(commit.get("author_email", "orgos-integrator@local")))
print(str((scope.get("diff_budget") or {}).get("max_files", 0)))
print(str((scope.get("diff_budget") or {}).get("max_lines", 0)))
PY

item_status=$(sed -n '1p' "$item_values_path")
if [ "$item_status" != "OK" ]; then
  rm -f "$item_values_path"
  fail_processing "${item_status#ERROR:}"
fi

worktree_path=$(sed -n '2p' "$item_values_path")
branch=$(sed -n '3p' "$item_values_path")
base_branch=$(sed -n '4p' "$item_values_path")
base_commit=$(sed -n '5p' "$item_values_path")
expected_head=$(sed -n '6p' "$item_values_path")
artifact_manifest=$(sed -n '7p' "$item_values_path")
verification_required=$(sed -n '8p' "$item_values_path")
verification_status=$(sed -n '9p' "$item_values_path")
commit_message=$(sed -n '10p' "$item_values_path")
author_name=$(sed -n '11p' "$item_values_path")
author_email=$(sed -n '12p' "$item_values_path")
max_files=$(sed -n '13p' "$item_values_path")
max_lines=$(sed -n '14p' "$item_values_path")
rm -f "$item_values_path"

[ -d "$worktree_path" ] || fail_processing "worktree path missing: $worktree_path"
[ -f "$artifact_manifest" ] || fail_processing "artifact manifest missing: $artifact_manifest"
[ -x "$VERIFIER" ] || fail_processing "artifact verifier missing or not executable: $VERIFIER"

if ! "$VERIFIER" "$artifact_manifest" >/dev/null 2>&1; then
  fail_processing "artifact manifest failed verification: $artifact_manifest"
fi

if [[ "$branch" == "main" || "$branch" == "develop" || "$base_branch" == "develop" ]]; then
  fail_processing "protected branch is not allowed for integration worktree: $branch"
fi

if [[ ! "$branch" =~ ^task/${task_id}-.+ ]]; then
  fail_processing "branch must match task/$task_id-...: $branch"
fi

current_branch=$(git -C "$worktree_path" branch --show-current)
if [ "$current_branch" != "$branch" ]; then
  fail_processing "worktree branch mismatch: expected $branch, got $current_branch"
fi

current_head=$(git -C "$worktree_path" rev-parse HEAD)
if [ -n "$expected_head" ] && [ "$current_head" != "$expected_head" ]; then
  fail_processing "worktree HEAD moved: expected $expected_head, got $current_head"
fi

if [ "$verification_required" = "true" ] && [ "$verification_status" != "passed" ]; then
  fail_processing "verification is required but status is $verification_status"
fi

if ! python3 - "$REPO_ROOT" "$processing_path" >/tmp/orgos-integrator-deps.$$ <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
queue_path = Path(sys.argv[2])
with queue_path.open("r", encoding="utf-8") as handle:
    data = json.load(handle)

dependencies = data.get("dependencies") or {}
tasks = dependencies.get("tasks") or []
queue_items = dependencies.get("queue_items") or []
done_root = root / ".ai" / "queue" / "integration" / "done"

def task_done(task_id: str) -> bool:
    return any(done_root.glob(f"*/{task_id}.*.json"))

def queue_item_done(item_id: str) -> bool:
    for candidate in done_root.glob("*/*.json"):
        try:
            with candidate.open("r", encoding="utf-8") as handle:
                item = json.load(handle)
        except Exception:
            continue
        if item.get("item_id") == item_id and item.get("status") == "done":
            return True
    return False

missing_tasks = [task for task in tasks if not task_done(str(task))]
missing_items = [item for item in queue_items if not queue_item_done(str(item))]
if missing_tasks or missing_items:
    print(
        "dependencies not done: "
        + ", ".join([*(f"task:{task}" for task in missing_tasks), *(f"queue:{item}" for item in missing_items)])
    )
    raise SystemExit(1)
PY
then
  dep_error=$(cat /tmp/orgos-integrator-deps.$$ 2>/dev/null || true)
  rm -f /tmp/orgos-integrator-deps.$$
  fail_processing "${dep_error:-dependency validation failed}"
fi
rm -f /tmp/orgos-integrator-deps.$$

changed_files=()
changed_files_path=$(mktemp "${TMPDIR:-/tmp}/orgos-integrator-changed.XXXXXX")
python3 - "$worktree_path" >"$changed_files_path" <<'PY'
import subprocess
import sys

worktree = sys.argv[1]
output = subprocess.check_output(["git", "-C", worktree, "status", "--porcelain"], text=True)
paths = []
for line in output.splitlines():
    if len(line) < 4:
        continue
    path = line[3:]
    if " -> " in path:
        path = path.split(" -> ", 1)[1]
    paths.append(path)
for path in sorted(set(paths)):
    print(path)
PY
while IFS= read -r changed_file; do
  [ -n "$changed_file" ] && changed_files+=("$changed_file")
done < "$changed_files_path"
rm -f "$changed_files_path"

if [ "${#changed_files[@]}" -eq 0 ]; then
  fail_processing "no worktree changes to commit"
fi

if ! python3 - "$processing_path" "$worktree_path" "${changed_files[@]}" >/tmp/orgos-integrator-diff.$$ <<'PY'
import fnmatch
import json
import subprocess
import sys
from pathlib import Path

queue_path = Path(sys.argv[1])
worktree = Path(sys.argv[2])
changed = sys.argv[3:]
with queue_path.open("r", encoding="utf-8") as handle:
    data = json.load(handle)

scope = data.get("scope") or {}
allowed = [str(item) for item in scope.get("allowed_paths") or []]
prohibited = [str(item) for item in scope.get("prohibited_paths") or []]
if not allowed:
    print("scope.allowed_paths must not be empty")
    raise SystemExit(1)

def matches(path: str, pattern: str) -> bool:
    return fnmatch.fnmatch(path, pattern) or path == pattern

for path in changed:
    if any(matches(path, pattern) for pattern in prohibited):
        print(f"changed path is prohibited: {path}")
        raise SystemExit(1)
    if not any(matches(path, pattern) for pattern in allowed):
        print(f"changed path is outside allowed_paths: {path}")
        raise SystemExit(1)

tracked_output = subprocess.check_output(
    ["git", "-C", str(worktree), "diff", "--numstat", "HEAD", "--", *changed],
    text=True,
)
line_count = 0
covered = set()
for line in tracked_output.splitlines():
    parts = line.split("\t")
    if len(parts) < 3:
        continue
    added, deleted, path = parts[0], parts[1], parts[2]
    covered.add(path)
    if added != "-":
        line_count += int(added)
    if deleted != "-":
        line_count += int(deleted)

for path in changed:
    if path in covered:
        continue
    candidate = worktree / path
    if candidate.is_file():
        try:
            line_count += len(candidate.read_text(encoding="utf-8", errors="ignore").splitlines())
        except OSError:
            line_count += 1

print(line_count)
PY
then
  diff_error=$(cat /tmp/orgos-integrator-diff.$$ 2>/dev/null || true)
  rm -f /tmp/orgos-integrator-diff.$$
  fail_processing "${diff_error:-diff validation failed}"
fi
diff_lines=$(cat /tmp/orgos-integrator-diff.$$)
rm -f /tmp/orgos-integrator-diff.$$

if [ "$max_files" -gt 0 ] && [ "${#changed_files[@]}" -gt "$max_files" ]; then
  fail_processing "diff budget exceeded: ${#changed_files[@]} files > $max_files"
fi
if [ "$max_lines" -gt 0 ] && [ "$diff_lines" -gt "$max_lines" ]; then
  fail_processing "diff budget exceeded: $diff_lines lines > $max_lines"
fi

git -C "$worktree_path" add -- "${changed_files[@]}"

if ! git -C "$worktree_path" \
  -c user.name="$author_name" \
  -c user.email="$author_email" \
  commit -m "$commit_message" --author="$author_name <$author_email>" >/tmp/orgos-integrator-commit.$$ 2>&1; then
  commit_error=$(cat /tmp/orgos-integrator-commit.$$)
  rm -f /tmp/orgos-integrator-commit.$$
  fail_processing "git commit failed: $commit_error"
fi
rm -f /tmp/orgos-integrator-commit.$$

commit_sha=$(git -C "$worktree_path" rev-parse HEAD)
integrated_at=$(date -u +%Y%m%dT%H%M%SZ)
integrated_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
done_month=$(date -u +%Y%m)
done_month_dir="$done_dir/$done_month"
done_path="$done_month_dir/$task_id.$integrated_at.json"
mkdir -p "$done_month_dir"

python3 - "$processing_path" "$commit_sha" "$integrated_iso" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
commit_sha = sys.argv[2]
integrated_at = sys.argv[3]
with path.open("r", encoding="utf-8") as handle:
    data = json.load(handle)
data["status"] = "done"
data.setdefault("commit", {})["commit_sha"] = commit_sha
data.setdefault("commit", {})["integrated_at"] = integrated_at
with path.open("w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

mv "$processing_path" "$done_path"
printf '%s\n' "$commit_sha"
printf 'done queue item: %s\n' "$done_path"
