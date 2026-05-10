#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
JSON_OUTPUT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      JSON_OUTPUT=1
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ "$JSON_OUTPUT" -ne 1 ]]; then
  echo "memory-scanner requires --json" >&2
  exit 1
fi

NORMALIZE_JSON="$(bash "$REPO_ROOT/scripts/memory/normalize-lint.sh" --json)"
export NORMALIZE_JSON

python3 - "$REPO_ROOT" <<'PY'
from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

repo = Path(sys.argv[1])
now = datetime.now(timezone.utc).replace(microsecond=0)
detected_at = now.isoformat().replace("+00:00", "Z")
events: list[dict[str, Any]] = []


def rel(path: Path) -> str:
    try:
        return str(path.relative_to(repo))
    except ValueError:
        return str(path)


def emit_rule_stale(path: str, line: int, snippet: str, confidence: float = 0.82) -> None:
    events.append({
        "detected_at": detected_at,
        "source": "memory_scanner",
        "event_type": "rule_stale",
        "severity": "P2",
        "confidence": confidence,
        "novelty": "recurring",
        "target_artifacts": [{"path": path, "lines": [line] if line > 0 else []}],
        "evidence": [{"kind": "duplication_signal", "snippet": snippet}],
        "proposed_action": "deduplicate",
        "estimated_impact": "medium",
        "estimated_risk": "medium",
        "autonomy_candidate": "ask_before_execute",
        "blast_radius": "multi_file",
        "recommended_next": "Bundle overlapping rule or memory semantics into a follow-up deduplication proposal with explicit rollback.",
    })


try:
    normalize_payload = json.loads(__import__("os").environ.get("NORMALIZE_JSON", "{}"))
except json.JSONDecodeError:
    normalize_payload = {"status": "failed", "warnings": []}

for warning in normalize_payload.get("warnings", []) or []:
    if not isinstance(warning, dict):
        continue
    fact_ids = warning.get("fact_ids") or []
    emit_rule_stale(
        ".ai/USER_PROFILE.yaml",
        1,
        f"normalize-lint {warning.get('kind', 'warning')}: {warning.get('message', fact_ids)}",
        confidence=0.9,
    )

rules_dir = repo / ".claude" / "rules"
heading_index: dict[str, list[tuple[Path, int, str]]] = {}
if rules_dir.exists():
    for path in sorted(rules_dir.glob("*.md")):
        for line_no, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            match = re.match(r"^\s{0,3}#{1,3}\s+(.+?)\s*$", raw)
            if not match:
                continue
            heading = re.sub(r"[\s:：()（）「」『』`*_/-]+", " ", match.group(1).strip().lower())
            heading = re.sub(r"\s+", " ", heading).strip()
            if len(heading) < 8:
                continue
            heading_index.setdefault(heading, []).append((path, line_no, match.group(1).strip()))

for heading, occurrences in sorted(heading_index.items()):
    files = sorted({rel(path) for path, _, _ in occurrences})
    if len(files) < 2:
        continue
    first_path, first_line, first_heading = occurrences[0]
    emit_rule_stale(
        rel(first_path),
        first_line,
        f"Duplicate rule heading '{first_heading}' appears in {', '.join(files[:4])}",
        confidence=0.78,
    )
    if len(events) >= 20:
        break

print(json.dumps(events, ensure_ascii=False, separators=(",", ":")))
PY
