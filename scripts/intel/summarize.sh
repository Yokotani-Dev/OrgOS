#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
RAW_DIR="${INTEL_RAW_DIR:-$REPO_ROOT/.ai/INTELLIGENCE/raw}"
WEEKLY_DIR="${INTEL_WEEKLY_DIR:-$REPO_ROOT/.ai/INTELLIGENCE/weekly}"
RUN_DATE="${INTEL_RUN_DATE:-$(date -u +%F)}"

mkdir -p "$WEEKLY_DIR"

python3 - "$REPO_ROOT" "$RAW_DIR" "$WEEKLY_DIR" "$RUN_DATE" <<'PY'
from __future__ import annotations

import datetime as dt
import html
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

repo = Path(sys.argv[1])
raw_dir = Path(sys.argv[2])
weekly_dir = Path(sys.argv[3])
run_date = dt.date.fromisoformat(sys.argv[4])
window_start = run_date - dt.timedelta(days=6)
iso_year, iso_week, _ = run_date.isocalendar()
week_id = f"{iso_year}-W{iso_week:02d}"
output = weekly_dir / f"{week_id}.md"

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

def file_date(path: Path) -> dt.date | None:
    match = re.search(r"(\d{4}-\d{2}-\d{2})", path.name)
    if not match:
        return None
    try:
        return dt.date.fromisoformat(match.group(1))
    except ValueError:
        return None

def strip_ns(tag: str) -> str:
    return tag.rsplit("}", 1)[-1].lower()

def text_of(parent: ET.Element, names: set[str]) -> str:
    for child in parent:
        if strip_ns(child.tag) in names and child.text:
            return " ".join(child.text.split())
    return ""

def xml_items(path: Path) -> list[dict[str, str]]:
    try:
        root = ET.fromstring(path.read_text(encoding="utf-8", errors="replace"))
    except Exception:
        log("warn", "raw_parse_failed", "unable to parse XML source", path=rel(path))
        return []

    nodes = [node for node in root.iter() if strip_ns(node.tag) in {"item", "entry"}]
    items: list[dict[str, str]] = []
    for node in nodes[:12]:
        title = text_of(node, {"title"}) or "(untitled)"
        published = text_of(node, {"published", "updated", "pubdate", "date"})
        link = text_of(node, {"link"})
        if not link:
            for child in node:
                if strip_ns(child.tag) == "link":
                    link = child.attrib.get("href", "")
                    if link:
                        break
        items.append({"title": html.unescape(title), "date": published, "link": link})
    return items

def collect_json_titles(value: Any, results: list[dict[str, str]]) -> None:
    if len(results) >= 12:
        return
    if isinstance(value, dict):
        title = value.get("title") or value.get("name")
        if isinstance(title, str) and title.strip():
            link = value.get("url") or value.get("link") or ""
            date = value.get("published_at") or value.get("published") or value.get("date") or value.get("created_at") or ""
            results.append({"title": " ".join(title.split()), "date": str(date), "link": str(link)})
        for child in value.values():
            collect_json_titles(child, results)
    elif isinstance(value, list):
        for child in value:
            collect_json_titles(child, results)

def json_items(path: Path) -> list[dict[str, str]]:
    try:
        data = json.loads(path.read_text(encoding="utf-8", errors="replace"))
    except Exception:
        log("warn", "raw_parse_failed", "unable to parse JSON source", path=rel(path))
        return []
    results: list[dict[str, str]] = []
    collect_json_titles(data, results)
    return results

raw_files = []
if raw_dir.exists():
    for path in raw_dir.rglob("*"):
        if not path.is_file() or path.name == ".gitkeep":
            continue
        observed = file_date(path)
        if observed and window_start <= observed <= run_date:
            raw_files.append(path)

source_summaries: list[dict[str, Any]] = []
for path in sorted(raw_files):
    source_id = path.parent.name
    if path.suffix.lower() == ".json":
        items = json_items(path)
    else:
        items = xml_items(path)
    source_summaries.append({"source_id": source_id, "path": rel(path), "items": items})

total_items = sum(len(source["items"]) for source in source_summaries)
lines = [
    f"# Weekly Intelligence Summary: {week_id}",
    "",
    f"- generated_at: {dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace('+00:00', 'Z')}",
    f"- window: {window_start.isoformat()}..{run_date.isoformat()}",
    f"- sources_read: {len(source_summaries)}",
    f"- items_found: {total_items}",
    "- summarizer: fixture-stub-v1",
    "",
    "## Highlights",
]

if total_items == 0:
    lines.append("- No fresh source items were available in the seven-day window.")
else:
    for source in source_summaries:
        items = source["items"]
        if not items:
            continue
        first = items[0]
        suffix = f" ({first['date']})" if first.get("date") else ""
        lines.append(f"- {source['source_id']}: {first['title']}{suffix}")

lines.extend(["", "## Source References"])
if source_summaries:
    for source in source_summaries:
        lines.append(f"- {source['path']}")
else:
    lines.append("- none")

lines.extend(["", "## Extracted Items"])
if total_items == 0:
    lines.append("- none")
else:
    for source in source_summaries:
        for item in source["items"][:5]:
            link = f" - {item['link']}" if item.get("link") else ""
            lines.append(f"- [{source['source_id']}] {item['title']}{link}")

lines.extend([
    "",
    "## Suggested OrgOS Signals",
    "- Review whether source changes imply updates to agent workflows, evals, or integration runbooks.",
    "- Keep all generated OIP candidates in proposal status until Owner or Manager approval.",
])

output.write_text("\n".join(lines) + "\n", encoding="utf-8")
log("info", "summary_written", "weekly summary generated", path=rel(output), sources_read=len(source_summaries), items_found=total_items)
PY
