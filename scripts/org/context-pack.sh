#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/org/context-pack.sh [--task T-XXX] [--include-rules] [--include-tasks] [--output PATH]

Build a redacted OrgOS context pack for external LLM review.
Default output: /tmp/orgos-context-pack-<ts>.md
USAGE
}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=${ORGOS_CONTEXT_PACK_REPO_ROOT:-${ORGOS_CONTEXT_PACK_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}}
REDACTOR="$SCRIPT_DIR/redact-secrets.py"
MAX_BYTES=${ORGOS_CONTEXT_PACK_MAX_BYTES:-102400}
MAX_FILE_BYTES=${ORGOS_CONTEXT_PACK_MAX_FILE_BYTES:-102400}

include_rules=0
include_tasks=0
task_id=""
output_path=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --include-rules)
      include_rules=1
      ;;
    --include-tasks)
      include_tasks=1
      ;;
    --task)
      if [ "$#" -lt 2 ] || [ -z "${2:-}" ]; then
        printf 'context-pack.sh: --task requires a value\n' >&2
        exit 2
      fi
      task_id=$2
      shift
      ;;
    --output)
      if [ "$#" -lt 2 ] || [ -z "${2:-}" ]; then
        printf 'context-pack.sh: --output requires a value\n' >&2
        exit 2
      fi
      output_path=$2
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'context-pack.sh: unknown option: %s\n' "$1" >&2
      usage
      exit 2
      ;;
  esac
  shift
done

if [ ! -x "$REDACTOR" ]; then
  printf 'context-pack.sh: redactor not found or not executable: %s\n' "$REDACTOR" >&2
  exit 1
fi

if ! [[ "$MAX_BYTES" =~ ^[0-9]+$ ]] || [ "$MAX_BYTES" -lt 256 ]; then
  printf 'context-pack.sh: ORGOS_CONTEXT_PACK_MAX_BYTES must be an integer >= 256\n' >&2
  exit 2
fi

if ! [[ "$MAX_FILE_BYTES" =~ ^[0-9]+$ ]] || [ "$MAX_FILE_BYTES" -lt 256 ]; then
  printf 'context-pack.sh: ORGOS_CONTEXT_PACK_MAX_FILE_BYTES must be an integer >= 256\n' >&2
  exit 2
fi

if [ -n "$task_id" ] && ! [[ "$task_id" =~ ^[A-Za-z0-9._-]+$ ]]; then
  printf 'context-pack.sh: invalid task id: %s\n' "$task_id" >&2
  exit 2
fi

if [ -z "$output_path" ]; then
  output_path="/tmp/orgos-context-pack-$(date -u '+%Y%m%dT%H%M%SZ').md"
fi

tmp_output=$(mktemp "${TMPDIR:-/tmp}/orgos-context-pack.XXXXXX")
trap 'rm -f "$tmp_output"' EXIT

append_line() {
  printf '%s\n' "$*" >> "$tmp_output"
}

append_blank() {
  printf '\n' >> "$tmp_output"
}

append_redacted_stream() {
  "$REDACTOR" >> "$tmp_output"
}

is_forbidden_context_path() {
  local rel_path="$1"
  case "$rel_path" in
    .env|.env.*|*/.env|*/.env.*|secrets/*|*/secrets/*) return 0 ;;
    *) return 1 ;;
  esac
}

append_file() {
  local rel_path="$1"
  local abs_path="$REPO_ROOT/$rel_path"
  local size_bytes

  append_line "## $rel_path"
  append_blank
  if is_forbidden_context_path "$rel_path"; then
    append_line "_Skipped forbidden secret path: ${rel_path}_"
    append_blank
    return
  fi

  if [ ! -f "$abs_path" ]; then
    append_line "_Missing: ${rel_path}_"
    append_blank
    return
  fi

  size_bytes=$(wc -c < "$abs_path" | tr -d ' ')
  append_line '````text'
  head -c "$MAX_FILE_BYTES" "$abs_path" | append_redacted_stream
  append_line ''
  if [ "$size_bytes" -gt "$MAX_FILE_BYTES" ]; then
    append_line "[TRUNCATED: file exceeded ${MAX_FILE_BYTES} bytes]"
  fi
  append_line '````'
  append_blank
}

append_active_tasks() {
  local tasks_path="$REPO_ROOT/.ai/TASKS.yaml"

  append_line "## Active Tasks"
  append_blank
  if [ ! -f "$tasks_path" ]; then
    append_line "_Missing: .ai/TASKS.yaml_"
    append_blank
    return
  fi

  python3 - "$tasks_path" <<'PY' | append_redacted_stream
from __future__ import annotations

import sys

try:
    import yaml
except ImportError as exc:
    raise SystemExit(f"PyYAML is required to parse TASKS.yaml: {exc}")

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = yaml.safe_load(handle) or {}

tasks = data.get("tasks") or []
active = [task for task in tasks if task.get("status") in {"queued", "running"}]

if not active:
    print("_No active tasks found._")
    raise SystemExit(0)

for task in active:
    print(f"- {task.get('id', '<missing-id>')}: {task.get('title', '')}")
    for key in ("status", "priority", "owner_role", "risk_level", "blast_radius"):
        if key in task:
            print(f"  {key}: {task[key]}")
    deps = task.get("deps")
    if deps:
        print("  deps: " + ", ".join(str(dep) for dep in deps))
    allowed_paths = task.get("allowed_paths")
    if allowed_paths:
        print("  allowed_paths:")
        for path in allowed_paths:
            print(f"    - {path}")
    print()
PY
  append_blank
}

append_rules() {
  append_line "## Rules"
  append_blank

  local found=0
  while IFS= read -r rule_path; do
    found=1
    append_file "${rule_path#"$REPO_ROOT"/}"
  done < <(find "$REPO_ROOT/.claude/rules" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort)

  if [ "$found" -eq 0 ]; then
    append_line "_No .claude/rules/*.md files found._"
    append_blank
  fi
}

append_task_context() {
  local id="$1"

  append_line "## Task Context: $id"
  append_blank
  append_file ".ai/_machine/codex/ORDERS/$id.md"
  append_file ".ai/HANDOFF.md"
  append_file ".ai/_machine/codex/RESULTS/$id.md"
  append_file ".ai/_machine/codex/RESULTS/$id.txt"
  append_file ".ai/_machine/codex/RESULTS/$id.json"
  append_file ".ai/_machine/review/PACKETS/$id.md"

  append_line "## Artifact Manifests: $id"
  append_blank

  local found=0
  while IFS= read -r manifest_path; do
    found=1
    append_file "${manifest_path#"$REPO_ROOT"/}"
  done < <(
    {
      find "$REPO_ROOT/.ai/_machine/artifacts/$id" -type f -name artifact_manifest.json 2>/dev/null
    } | sort || true
  )

  if [ "$found" -eq 0 ]; then
    append_line "_No artifact manifests found for $id._"
    append_blank
  fi
}

write_capped_output() {
  local source_path="$1"
  local dest_path="$2"
  local max_bytes="$3"

  mkdir -p "$(dirname "$dest_path")"
  python3 - "$source_path" "$dest_path" "$max_bytes" <<'PY'
from __future__ import annotations

import sys
from pathlib import Path

source = Path(sys.argv[1])
dest = Path(sys.argv[2])
max_bytes = int(sys.argv[3])
data = source.read_bytes()

if len(data) <= max_bytes:
    dest.write_bytes(data)
    raise SystemExit(0)

marker = f"\n\n[TRUNCATED: context pack exceeded {max_bytes} bytes]\n".encode("utf-8")
body_limit = max(0, max_bytes - len(marker))
body = data[:body_limit].decode("utf-8", errors="ignore").encode("utf-8")
while len(body) + len(marker) > max_bytes:
    body = body[:-1]
dest.write_bytes(body + marker)
PY
}

append_line "# OrgOS Context Pack"
append_blank
append_line "- generated_at: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
append_line "- repo_root: $REPO_ROOT"
append_line "- max_bytes: $MAX_BYTES"
if [ -n "$task_id" ]; then
  append_line "- task: $task_id"
fi
append_blank

if [ -n "$task_id" ]; then
  append_task_context "$task_id"
fi

if [ "$include_tasks" -eq 1 ]; then
  append_active_tasks
fi

if [ "$include_rules" -eq 1 ]; then
  append_rules
fi

if [ "$include_rules" -eq 0 ] && [ "$include_tasks" -eq 0 ] && [ -z "$task_id" ]; then
  append_line "_No context selectors were provided._"
  append_blank
fi

write_capped_output "$tmp_output" "$output_path" "$MAX_BYTES"
printf '%s\n' "$output_path"
