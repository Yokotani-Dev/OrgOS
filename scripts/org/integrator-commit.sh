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
PLAN_SCHEMA="$REPO_ROOT/.claude/schemas/plan-contract.v1.json"

# Returns 0 (true) when .ai/CONTROL.yaml grants allow_main_mutation: true.
control_allows_main_mutation() {
  local repo_root="$1"
  python3 - "$repo_root" <<'PY'
import sys
from pathlib import Path

control = Path(sys.argv[1]) / ".ai" / "CONTROL.yaml"
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
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("#"):
            continue
        if stripped.replace(" ", "").lower().startswith("allow_main_mutation:"):
            raw = stripped.split(":", 1)[1].strip().strip('"').strip("'").lower()
            value = raw in {"true", "yes", "1", "on"}
            break

raise SystemExit(0 if value is True else 1)
PY
}

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

read_queue_task_id() {
  local path="$1"
  python3 - "$path" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
except Exception as exc:
    print(f"ERROR:failed to parse queue item: {exc}")
    raise SystemExit(0)
task_id = data.get("task_id")
if not isinstance(task_id, str) or not task_id:
    print("ERROR:queue item missing task_id")
    raise SystemExit(0)
print(task_id)
PY
}

if [ -z "$task_id" ] && [ -n "$queue_item" ]; then
  queue_task_id=$(read_queue_task_id "$queue_item")
  if [[ "$queue_task_id" == ERROR:* ]]; then
    echo "${queue_task_id#ERROR:}" >&2
    exit 2
  fi
  task_id="$queue_task_id"
fi

if [ -z "$task_id" ]; then
  echo "missing --task-id" >&2
  usage
  exit 2
fi

if [[ ! "$task_id" =~ ^T-[A-Z0-9]+-[A-Z0-9-]+$ ]]; then
  echo "invalid task_id: $task_id" >&2
  exit 2
fi

queue_root="$REPO_ROOT/.ai/_machine/queue/integration"
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

queue_task_id=$(read_queue_task_id "$queue_item")
if [[ "$queue_task_id" == ERROR:* ]]; then
  echo "${queue_task_id#ERROR:}" >&2
  exit 2
fi
if [ "$queue_task_id" != "$task_id" ]; then
  echo "queue item task_id mismatch: expected $task_id, got $queue_task_id" >&2
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
  python3 - "$queue_root/events.jsonl" "$task_id" "$message" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

events_path = Path(sys.argv[1])
task_id = sys.argv[2]
message = sys.argv[3]
events_path.parent.mkdir(parents=True, exist_ok=True)
payload = {
    "event": "IntegrationFailed",
    "task_id": task_id,
    "message": message,
    "occurred_at": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
}
with events_path.open("a", encoding="utf-8") as handle:
    handle.write(json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n")
PY
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

# Validate the plan contract against the SELECTED change set (the scope-intersected
# files this integrator will actually commit), not the whole worktree. A shared dirty
# tree may carry unrelated changes outside this task's paths; partitioned integration
# must not be blocked by them. The selected paths are passed as positional args.
validate_plan_contract() {
  local plan_path="$REPO_ROOT/.ai/_machine/plans/$task_id.plan.yaml"

  if [ ! -f "$PLAN_SCHEMA" ] && [ ! -f "$plan_path" ]; then
    return 0
  fi

  python3 - "$task_id" "$plan_path" "$PLAN_SCHEMA" "$@" <<'PY'
import fnmatch
import json
import sys
from pathlib import Path

try:
    import yaml
    from jsonschema import Draft202012Validator
except Exception as exc:
    print(f"plan contract validator dependency missing: {exc}")
    raise SystemExit(1)

task_id = sys.argv[1]
plan_path = Path(sys.argv[2])
schema_path = Path(sys.argv[3])
selected = [path for path in sys.argv[4:] if path]

if not plan_path.is_file():
    print(f"plan contract missing: {plan_path}")
    raise SystemExit(1)
if not schema_path.is_file():
    print(f"plan schema missing: {schema_path}")
    raise SystemExit(1)

try:
    with schema_path.open("r", encoding="utf-8") as handle:
        schema = json.load(handle)
except Exception as exc:
    print(f"plan schema is not valid JSON: {exc}")
    raise SystemExit(1)

try:
    with plan_path.open("r", encoding="utf-8") as handle:
        plan = yaml.safe_load(handle)
except Exception as exc:
    print(f"plan contract is not valid YAML: {exc}")
    raise SystemExit(1)

try:
    Draft202012Validator(schema).validate(plan)
except Exception as exc:
    print(f"plan contract failed schema validation: {exc.message}")
    raise SystemExit(1)

if not isinstance(plan, dict):
    print("plan contract must be an object")
    raise SystemExit(1)
if plan.get("task_id") not in (None, task_id):
    print(f"plan task_id mismatch: expected {task_id}, got {plan.get('task_id')}")
    raise SystemExit(1)

allowed = [str(item) for item in plan.get("allowed_paths") or []]
if not allowed:
    print("plan allowed_paths must not be empty")
    raise SystemExit(1)

def matches(path: str, pattern: str) -> bool:
    if path == pattern:
        return True
    if pattern.endswith("/") and path.startswith(pattern):
        return True
    if not any(char in pattern for char in "*?[") and path.startswith(pattern.rstrip("/") + "/"):
        return True
    return fnmatch.fnmatch(path, pattern)

# Only the staged/selected change set is validated against the plan — the whole
# worktree is intentionally NOT diffed so unrelated dirty files cannot block this task.
changed = sorted(set(selected))
outside = [path for path in changed if not any(matches(path, pattern) for pattern in allowed)]
if outside:
    print("changed file outside plan allowed_paths: " + ", ".join(outside))
    raise SystemExit(1)
PY
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
print("true" if commit.get("main_integration") is True else "false")
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
main_integration=$(sed -n '15p' "$item_values_path")
rm -f "$item_values_path"

[ -d "$worktree_path" ] || fail_processing "worktree path missing: $worktree_path"
[ -f "$artifact_manifest" ] || fail_processing "artifact manifest missing: $artifact_manifest"
[ -x "$VERIFIER" ] || fail_processing "artifact verifier missing or not executable: $VERIFIER"

if ! "$VERIFIER" "$artifact_manifest" >/dev/null 2>&1; then
  fail_processing "artifact manifest failed verification: $artifact_manifest"
fi

# develop is never a valid integration target (worktree branch or base), regardless
# of mode. ProtectedBranchNoTouch is preserved for every protected branch but main.
if [[ "$branch" == "develop" || "$base_branch" == "develop" ]]; then
  fail_processing "protected branch is not allowed for integration worktree: $branch"
fi

# Sanctioned main integration: branch == main is allowed ONLY when the queue item
# was created with --allow-main AND CONTROL.yaml still grants allow_main_mutation.
if [[ "$branch" == "main" ]]; then
  if [ "$main_integration" != "true" ]; then
    fail_processing "protected branch is not allowed for integration worktree: $branch"
  fi
  if ! control_allows_main_mutation "$REPO_ROOT"; then
    fail_processing "main integration denied: CONTROL.yaml allow_main_mutation must be true"
  fi
fi

if [ "$main_integration" != "true" ] && [[ ! "$branch" =~ ^task/${task_id}-.+ ]]; then
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
done_root = root / ".ai" / "_machine" / "queue" / "integration" / "done"

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
if ! python3 - "$worktree_path" "$processing_path" >"$changed_files_path" <<'PY'
import fnmatch
import json
import subprocess
import sys
from pathlib import Path

worktree = sys.argv[1]
queue_path = Path(sys.argv[2])
with queue_path.open("r", encoding="utf-8") as handle:
    data = json.load(handle)

scope = data.get("scope") or {}
allowed = [str(item) for item in scope.get("allowed_paths") or []]
prohibited = [str(item) for item in scope.get("prohibited_paths") or []]
if not allowed:
    print("scope.allowed_paths must not be empty")
    raise SystemExit(1)

def matches(path: str, pattern: str) -> bool:
    if path == pattern:
        return True
    if pattern.endswith("/") and path.startswith(pattern):
        return True
    if not any(char in pattern for char in "*?[") and path.startswith(pattern.rstrip("/") + "/"):
        return True
    return fnmatch.fnmatch(path, pattern)

output = subprocess.check_output(
    ["git", "-C", worktree, "status", "--porcelain", "--untracked-files=all"],
    text=True,
)
all_paths = []
for line in output.splitlines():
    if len(line) < 4:
        continue
    path = line[3:]
    if " -> " in path:
        path = path.split(" -> ", 1)[1]
    all_paths.append(path)

user_diff = sorted(
    path
    for path in set(all_paths)
    if any(matches(path, pattern) for pattern in allowed)
)
if not user_diff:
    print("no user diff within allowed_paths")
    raise SystemExit(1)

for path in user_diff:
    if any(matches(path, pattern) for pattern in prohibited):
        print(f"changed path is prohibited: {path}")
        raise SystemExit(1)

for path in user_diff:
    print(path)
PY
then
  changed_error=$(cat "$changed_files_path" 2>/dev/null || true)
  rm -f "$changed_files_path"
  fail_processing "${changed_error:-changed file selection failed}"
fi
while IFS= read -r changed_file; do
  [ -n "$changed_file" ] && changed_files+=("$changed_file")
done < "$changed_files_path"
rm -f "$changed_files_path"

if ! python3 - "$worktree_path" "${changed_files[@]}" >/tmp/orgos-integrator-diff.$$ <<'PY'
import subprocess
import sys
from pathlib import Path

worktree = Path(sys.argv[1])
changed = sys.argv[2:]

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

# Pass only the selected change set so the plan contract is validated against what
# will actually be committed, not the entire (possibly shared/dirty) worktree.
if ! plan_error=$(validate_plan_contract "${changed_files[@]}" 2>&1); then
  fail_processing "${plan_error:-plan contract validation failed}"
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
