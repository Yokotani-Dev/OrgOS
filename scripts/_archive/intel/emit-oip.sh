#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
WEEKLY_DIR="${INTEL_WEEKLY_DIR:-$REPO_ROOT/.ai/_machine/intelligence/weekly}"
REPORTS_DIR="${INTEL_REPORTS_DIR:-$REPO_ROOT/.ai/_machine/intelligence/reports}"

mkdir -p "$REPORTS_DIR"

python3 - "$REPO_ROOT" "$WEEKLY_DIR" "$REPORTS_DIR" <<'PY'
from __future__ import annotations

import datetime as dt
import json
import re
import sys
from pathlib import Path
from typing import Any

repo = Path(sys.argv[1])
weekly_dir = Path(sys.argv[2])
reports_dir = Path(sys.argv[3])

def log(level: str, event: str, message: str, **extra: Any) -> None:
    payload = {
        "ts": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "level": level,
        "event": event,
        "message": message,
    }
    payload.update(extra)
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), file=sys.stderr)

def rel(path: Path) -> str:
    try:
        return str(path.relative_to(repo))
    except ValueError:
        return str(path)

summaries = sorted(
    [path for path in weekly_dir.glob("*.md") if path.is_file() and path.name != ".gitkeep"],
    key=lambda path: (path.stat().st_mtime, path.name),
)
if not summaries:
    log("warn", "summary_missing", "no weekly summary found; skipped OIP emission")
    raise SystemExit(0)

summary_path = summaries[-1]
summary = summary_path.read_text(encoding="utf-8", errors="replace")
week_match = re.search(r"(\d{4}-W\d{2})", summary_path.stem)
week_id = week_match.group(1) if week_match else summary_path.stem
oip_id = f"OIP-INTEL-{week_id}"
report_path = reports_dir / f"{oip_id}.md"

source_refs: list[str] = []
in_refs = False
for line in summary.splitlines():
    if line.strip() == "## Source References":
        in_refs = True
        continue
    if in_refs and line.startswith("## "):
        break
    if in_refs and line.startswith("- "):
        ref = line[2:].strip()
        if ref and ref != "none":
            source_refs.append(ref)

highlights: list[str] = []
in_highlights = False
for line in summary.splitlines():
    if line.strip() == "## Highlights":
        in_highlights = True
        continue
    if in_highlights and line.startswith("## "):
        break
    if in_highlights and line.startswith("- "):
        highlights.append(line[2:].strip())

has_items = any("No fresh source items" not in item for item in highlights) and bool(source_refs)
title = "Review weekly intelligence for OrgOS improvement signals" if has_items else "Keep Intelligence pipeline operational"
suggested_action = (
    "Route the weekly summary through T-OS-324 synthesis as proposal input; do not auto-apply changes."
    if has_items
    else "No external change signal was found; keep the generated report as an operational heartbeat."
)

lines = [
    f"# {oip_id}: {title}",
    "",
    f"id: {oip_id}",
    f"title: {title}",
    "status: candidate",
    "origin: intelligence-weekly",
    f"summary_ref: {rel(summary_path)}",
    "handoff_target: T-OS-324",
    "approval_required: Owner / Manager",
    "",
    "## source_refs",
]
if source_refs:
    lines.extend(f"- {ref}" for ref in source_refs)
else:
    lines.append("- none")

lines.extend([
    "",
    "## evidence",
])
if highlights:
    lines.extend(f"- {item}" for item in highlights[:8])
else:
    lines.append("- No highlights were present in the weekly summary.")

lines.extend([
    "",
    "## suggested_action",
    suggested_action,
    "",
    "## safety",
    "- This is a proposal artifact only.",
    "- It must not be applied automatically.",
    "- Source URLs remain configured in .ai/_machine/intelligence/config.yaml.",
])

report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
log("info", "oip_written", "OIP candidate generated", path=rel(report_path), summary=rel(summary_path), source_refs=len(source_refs))
PY
