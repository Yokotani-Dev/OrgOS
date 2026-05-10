#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/.ai/INTEGRITY}"
NOW_OVERRIDE="${ORGOS_INTEGRITY_NOW:-}"

usage() {
  cat <<'EOF'
Usage: bash scripts/integrity/scan-stale.sh [options]

Options:
  --repo-root <path>    Repository root. Defaults to the current OrgOS repo.
  --output-dir <path>  Directory for scan-<timestamp>.md. Defaults to .ai/INTEGRITY.
  --now <iso8601>      Override scan clock for fixture tests.
  -h, --help           Show this help.

Scans:
  - OIP age > 90 days
  - capability verified_at / last_verified_at age > 30 days, or never verified
  - DECISIONS pending entries > 14 days
  - TASKS queued entries without activity in > 30 days
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root)
      REPO_ROOT="${2:-}"
      if [[ -z "$REPO_ROOT" ]]; then
        echo "--repo-root requires a path" >&2
        exit 2
      fi
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
      if [[ -z "$OUTPUT_DIR" ]]; then
        echo "--output-dir requires a path" >&2
        exit 2
      fi
      shift 2
      ;;
    --now)
      NOW_OVERRIDE="${2:-}"
      if [[ -z "$NOW_OVERRIDE" ]]; then
        echo "--now requires an ISO8601 timestamp" >&2
        exit 2
      fi
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

mkdir -p "$OUTPUT_DIR"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUTPUT_PATH="${OUTPUT_PATH:-$OUTPUT_DIR/scan-$TIMESTAMP.md}"

export REPO_ROOT OUTPUT_PATH NOW_OVERRIDE

python3 - <<'PY'
from __future__ import annotations

import json
import os
import re
import sys
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError as exc:
    print(
        json.dumps(
            {
                "level": "error",
                "event": "integrity_scan_failed",
                "error_class": "missing_dependency",
                "message": "PyYAML is required to parse OrgOS YAML ledgers.",
                "recovery": "Install PyYAML or run in the standard OrgOS environment.",
            },
            ensure_ascii=False,
        ),
        file=sys.stderr,
    )
    raise SystemExit(1) from exc


repo = Path(os.environ["REPO_ROOT"]).resolve()
output_path = Path(os.environ["OUTPUT_PATH"]).resolve()
now_override = os.environ.get("NOW_OVERRIDE", "")


def log(level: str, event: str, **fields: Any) -> None:
    payload = {"level": level, "event": event, **fields}
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), file=sys.stderr)


def fail(error_class: str, message: str, recovery: str) -> None:
    log("error", "integrity_scan_failed", error_class=error_class, message=message, recovery=recovery)
    raise SystemExit(1)


def utc_now() -> datetime:
    if not now_override:
        return datetime.now(timezone.utc).replace(microsecond=0)
    try:
        parsed = datetime.fromisoformat(now_override.replace("Z", "+00:00"))
    except ValueError:
        fail("invalid_argument", f"--now is not ISO8601: {now_override}", "Pass a value like 2026-05-10T00:00:00Z.")
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc).replace(microsecond=0)


now = utc_now()
today = now.date()


def rel(path: Path) -> str:
    try:
        return str(path.relative_to(repo))
    except ValueError:
        return str(path)


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        fail("missing_input", f"Required input is missing: {rel(path)}", "Restore the input file or run from a complete OrgOS checkout.")
    except UnicodeDecodeError:
        fail("invalid_input", f"Input is not valid UTF-8: {rel(path)}", "Convert the file to UTF-8 before scanning.")


def load_yaml(path: Path) -> Any:
    text = read_text(path)
    try:
        return yaml.safe_load(text) or {}
    except yaml.YAMLError as exc:
        fail("invalid_yaml", f"YAML parse failed for {rel(path)}: {exc}", "Fix the YAML syntax and rerun the scan.")


def parse_dateish(value: Any) -> date | None:
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    if not isinstance(value, str) or not value.strip():
        return None
    candidate = value.strip().strip("'\"")
    if candidate.endswith("Z"):
        candidate = candidate[:-1] + "+00:00"
    try:
        return datetime.fromisoformat(candidate).date()
    except ValueError:
        pass
    try:
        return date.fromisoformat(candidate[:10])
    except ValueError:
        return None


def age_days(value: date) -> int:
    return (today - value).days


def markdown_escape(value: Any) -> str:
    return str(value).replace("|", "\\|").replace("\n", " ")


def scan_oips() -> list[dict[str, Any]]:
    oip_dir = repo / ".ai" / "OIP"
    if not oip_dir.exists():
        return []

    status_patterns = [
        re.compile(r"^\s*>?\s*Status:\s*(.+?)\s*$", re.IGNORECASE),
        re.compile(r"^\s*[-*]?\s*\*\*ステータス\*\*\s*:\s*(.+?)\s*$"),
        re.compile(r"^\s*[-*]?\s*ステータス\s*:\s*(.+?)\s*$"),
    ]
    date_patterns = [
        re.compile(r"^\s*>?\s*Created:\s*([0-9]{4}-[0-9]{2}-[0-9]{2})\s*$", re.IGNORECASE),
        re.compile(r"^\s*>?\s*Date:\s*([0-9]{4}-[0-9]{2}-[0-9]{2})\s*$", re.IGNORECASE),
        re.compile(r"^\s*[-*]?\s*\*\*提案日\*\*\s*:\s*([0-9]{4}-[0-9]{2}-[0-9]{2})\s*$"),
        re.compile(r"^\s*[-*]?\s*提案日\s*:\s*([0-9]{4}-[0-9]{2}-[0-9]{2})\s*$"),
    ]

    findings: list[dict[str, Any]] = []
    for path in sorted(oip_dir.glob("*.md")):
        lines = read_text(path).splitlines()
        status = "unknown"
        created = None
        status_line = 1
        for idx, line in enumerate(lines, start=1):
            if status == "unknown":
                for pattern in status_patterns:
                    match = pattern.match(line)
                    if match:
                        status = match.group(1).strip().strip("*")
                        status_line = idx
                        break
            if created is None:
                for pattern in date_patterns:
                    match = pattern.match(line)
                    if match:
                        created = parse_dateish(match.group(1))
                        break
        if created is None:
            continue
        current_age = age_days(created)
        if current_age > 90:
            findings.append(
                {
                    "path": rel(path),
                    "line": status_line,
                    "status": status,
                    "created": created.isoformat(),
                    "age_days": current_age,
                }
            )
    return findings


def scan_capabilities() -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    data = load_yaml(repo / ".ai" / "CAPABILITIES.yaml")
    capabilities = data.get("capabilities", []) if isinstance(data, dict) else []
    stale: list[dict[str, Any]] = []
    unavailable: list[dict[str, Any]] = []
    for cap in capabilities if isinstance(capabilities, list) else []:
        if not isinstance(cap, dict):
            continue
        cap_id = cap.get("id", "unknown")
        status = cap.get("status", "unknown")
        verified = parse_dateish(cap.get("last_verified_at") or cap.get("verified_at"))
        if status != "available":
            unavailable.append({"id": cap_id, "status": status, "auth_status": cap.get("auth_status", "unknown")})
        if verified is None:
            stale.append({"id": cap_id, "status": status, "verified_at": "never", "age_days": "n/a"})
            continue
        current_age = age_days(verified)
        if current_age > 30:
            stale.append({"id": cap_id, "status": status, "verified_at": verified.isoformat(), "age_days": current_age})
    return stale, unavailable


def scan_decisions() -> list[dict[str, Any]]:
    text = read_text(repo / ".ai" / "DECISIONS.md")
    pending_match = re.search(r"^## Pending.*?$(.*?)(?=^## |\Z)", text, flags=re.MULTILINE | re.DOTALL)
    if not pending_match:
        return []
    pending = re.sub(r"<!--.*?-->", "", pending_match.group(1), flags=re.DOTALL)
    if "(なし)" in pending and "- ID:" not in pending:
        return []

    entries = re.split(r"(?m)^\s*-\s+ID:\s*", pending)
    findings: list[dict[str, Any]] = []
    for entry in entries[1:]:
        entry_text = "- ID: " + entry
        decision_id = entry.splitlines()[0].strip() if entry.splitlines() else "unknown"
        dates = [parse_dateish(match) for match in re.findall(r"\b(?:Date|Created|Requested|Updated):\s*([0-9]{4}-[0-9]{2}-[0-9]{2})", entry_text)]
        dates = [item for item in dates if item is not None]
        if not dates:
            findings.append({"id": decision_id, "date": "unknown", "age_days": "n/a", "reason": "pending_date_missing"})
            continue
        latest = max(dates)
        current_age = age_days(latest)
        if current_age > 14:
            findings.append({"id": decision_id, "date": latest.isoformat(), "age_days": current_age, "reason": "pending_over_14d"})
    return findings


def collect_dates(value: Any) -> list[date]:
    dates: list[date] = []
    if isinstance(value, dict):
        for key, nested in value.items():
            parsed_key = parse_dateish(key)
            if parsed_key:
                dates.append(parsed_key)
            dates.extend(collect_dates(nested))
    elif isinstance(value, list):
        for item in value:
            dates.extend(collect_dates(item))
    elif isinstance(value, (str, date, datetime)):
        parsed = parse_dateish(value)
        if parsed:
            dates.append(parsed)
        if isinstance(value, str):
            for match in re.findall(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", value):
                parsed_match = parse_dateish(match)
                if parsed_match:
                    dates.append(parsed_match)
    return dates


def scan_tasks() -> list[dict[str, Any]]:
    data = load_yaml(repo / ".ai" / "TASKS.yaml")
    tasks = data.get("tasks", []) if isinstance(data, dict) else []
    findings: list[dict[str, Any]] = []
    for task in tasks if isinstance(tasks, list) else []:
        if not isinstance(task, dict) or str(task.get("status", "")).lower() != "queued":
            continue
        dates = collect_dates(task)
        if not dates:
            findings.append({"id": task.get("id", "unknown"), "title": task.get("title", ""), "last_activity": "unknown", "age_days": "n/a"})
            continue
        latest = max(dates)
        current_age = age_days(latest)
        if current_age > 30:
            findings.append({"id": task.get("id", "unknown"), "title": task.get("title", ""), "last_activity": latest.isoformat(), "age_days": current_age})
    return findings


def table(headers: list[str], rows: list[list[Any]]) -> list[str]:
    lines = ["| " + " | ".join(headers) + " |", "| " + " | ".join(["---"] * len(headers)) + " |"]
    for row in rows:
        lines.append("| " + " | ".join(markdown_escape(item) for item in row) + " |")
    return lines


log("info", "integrity_scan_started", repo=str(repo), output=str(output_path), now=now.isoformat().replace("+00:00", "Z"))

oip_findings = scan_oips()
capability_stale, capability_unavailable = scan_capabilities()
decision_findings = scan_decisions()
task_findings = scan_tasks()

total_findings = len(oip_findings) + len(capability_stale) + len(decision_findings) + len(task_findings)

lines: list[str] = [
    f"# Integrity Scan: {now.strftime('%Y%m%dT%H%M%SZ')}",
    "",
    f"- Generated: {now.isoformat().replace('+00:00', 'Z')}",
    f"- Repository: {repo}",
    "- Thresholds: OIP age > 90d; capability verified age > 30d or never verified; DECISIONS pending > 14d; queued TASKS without activity > 30d",
    "",
    "## Summary",
    "",
]
lines.extend(
    table(
        ["Check", "Findings"],
        [
            ["OIP age > 90d", len(oip_findings)],
            ["Capability verification stale/never", len(capability_stale)],
            ["Capability unavailable", len(capability_unavailable)],
            ["DECISIONS pending > 14d", len(decision_findings)],
            ["TASKS queued inactive > 30d", len(task_findings)],
            ["Total stale findings", total_findings],
        ],
    )
)
lines.extend(["", "## OIP Age > 90d", ""])
if oip_findings:
    lines.extend(table(["Path", "Line", "Status", "Created", "Age Days"], [[item["path"], item["line"], item["status"], item["created"], item["age_days"]] for item in oip_findings]))
else:
    lines.append("No findings.")

lines.extend(["", "## Capability Verification Stale Or Never", ""])
if capability_stale:
    lines.extend(table(["Capability", "Status", "Verified At", "Age Days"], [[item["id"], item["status"], item["verified_at"], item["age_days"]] for item in capability_stale]))
else:
    lines.append("No findings.")

lines.extend(["", "## Capability Unavailable", ""])
if capability_unavailable:
    lines.extend(table(["Capability", "Status", "Auth Status"], [[item["id"], item["status"], item["auth_status"]] for item in capability_unavailable]))
else:
    lines.append("No findings.")

lines.extend(["", "## DECISIONS Pending > 14d", ""])
if decision_findings:
    lines.extend(table(["Decision", "Date", "Age Days", "Reason"], [[item["id"], item["date"], item["age_days"], item["reason"]] for item in decision_findings]))
else:
    lines.append("No findings.")

lines.extend(["", "## TASKS Queued Without Recent Activity > 30d", ""])
if task_findings:
    lines.extend(table(["Task", "Title", "Last Activity", "Age Days"], [[item["id"], item["title"], item["last_activity"], item["age_days"]] for item in task_findings]))
else:
    lines.append("No findings.")

lines.extend(
    [
        "",
        "## Recovery Guidance",
        "",
        "- Expired OIPs should be re-submitted as evolution proposals or closed by Manager.",
        "- Stale capabilities should be refreshed through `bash scripts/capabilities/scan.sh`; unavailable capabilities need environment or auth review.",
        "- Pending decisions older than 14 days should be escalated through Owner review.",
        "- Queued tasks without recent activity should be reprioritized, archived, or refreshed by Manager.",
        "",
    ]
)

try:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines), encoding="utf-8")
except OSError as exc:
    fail("write_failed", f"Could not write scan output: {exc}", "Check output directory permissions and rerun the scan.")

log(
    "info",
    "integrity_scan_completed",
    output=rel(output_path),
    total_findings=total_findings,
    oip_findings=len(oip_findings),
    capability_stale=len(capability_stale),
    capability_unavailable=len(capability_unavailable),
    decision_findings=len(decision_findings),
    task_findings=len(task_findings),
)
print(rel(output_path))
PY
