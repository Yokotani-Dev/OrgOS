#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HISTORY_FILE="$ROOT_DIR/.ai/DNA_HISTORY.yaml"

if [[ $# -ne 2 ]]; then
  printf 'Usage: scripts/dna/diff.sh <version_a> <version_b>\n' >&2
  exit 2
fi

if [[ ! -f "$HISTORY_FILE" ]]; then
  printf 'DNA history not found: %s\n' "$HISTORY_FILE" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  printf 'python3 is required\n' >&2
  exit 1
fi

python3 - "$HISTORY_FILE" "$1" "$2" <<'PY'
from __future__ import annotations

import sys

try:
    import yaml
except Exception as exc:
    print(f"PyYAML is required: {exc}", file=sys.stderr)
    sys.exit(1)

history_path, version_a, version_b = sys.argv[1:4]
with open(history_path, "r", encoding="utf-8") as fh:
    history = yaml.safe_load(fh) or {}

snapshots = {}
for entry in history.get("history") or []:
    if entry.get("version") and entry.get("snapshot"):
        snapshots[entry["version"]] = entry["snapshot"]

missing = [v for v in (version_a, version_b) if v not in snapshots]
if missing:
    print(f"version not found in DNA_HISTORY.yaml: {', '.join(missing)}", file=sys.stderr)
    sys.exit(1)


def index_components(dna):
    indexed = {}
    for kind, items in (dna.get("components") or {}).items():
        for item in items or []:
            indexed[item["path"]] = {
                "kind": kind,
                "id": item.get("id"),
                "checksum": item.get("checksum"),
                "version": item.get("version"),
                "classification": item.get("classification"),
                "depends_on": item.get("depends_on") or [],
            }
    return indexed


left = index_components(snapshots[version_a])
right = index_components(snapshots[version_b])
added = sorted(right.keys() - left.keys())
removed = sorted(left.keys() - right.keys())
modified = sorted(path for path in left.keys() & right.keys() if left[path] != right[path])

print(f"DNA diff {version_a} -> {version_b}")
print("added:")
for path in added:
    print(f"  - {path}")
print("removed:")
for path in removed:
    print(f"  - {path}")
print("modified:")
for path in modified:
    print(f"  - {path}")
if not added and not removed and not modified:
    print("no changes")
PY
