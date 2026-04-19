#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
JSONL_DIR="${JSONL_DIR:-$REPO_ROOT/.ai/METRICS/manager-quality}"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --jsonl-dir)
      JSONL_DIR="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

report_json="$("$PYTHON_BIN" "$REPO_ROOT/.claude/evals/manager-quality/report.py" regression --jsonl-dir "$JSONL_DIR" --json)"

export REPO_ROOT PYTHON_BIN JSONL_DIR DRY_RUN REPORT_JSON="$report_json"

"$PYTHON_BIN" - <<'PY'
from __future__ import annotations

import json
import os
import tempfile
from datetime import date
from pathlib import Path
from typing import Any


def build_mock_row(
    run_id: str,
    run_date: str,
    case_id: str,
    metric: str,
    passed: bool,
    current_pct: float,
    target_met: bool,
) -> dict[str, Any]:
    return {
        "run_id": run_id,
        "run_date": run_date,
        "suite": "manager-quality",
        "case_id": case_id,
        "title": case_id,
        "category": "mock",
        "symptom": "mock",
        "metric": metric,
        "metric_priority": "P1",
        "weight": 1.0,
        "passed": passed,
        "score": 1.0 if passed else 0.0,
        "reason": "mock",
        "expected_behavior": [],
        "anti_pattern": [],
        "metric_snapshot": {
            "metric_id": metric,
            "description": "mock",
            "priority": "P1",
            "target": "> 80%",
            "direction": "higher_is_better",
            "current_pct": current_pct,
            "cases": 1,
            "passed_cases": 1 if passed else 0,
            "failed_cases": 0 if passed else 1,
            "weighted_pass": 1.0 if passed else 0.0,
            "weighted_total": 1.0,
            "target_met": target_met,
        },
    }


def write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    with path.open("w", encoding="utf-8") as fh:
        for row in rows:
            fh.write(json.dumps(row, ensure_ascii=False) + "\n")


repo_root = Path(os.environ["REPO_ROOT"])
python_bin = os.environ["PYTHON_BIN"]
dry_run = os.environ["DRY_RUN"] == "1"
report = json.loads(os.environ["REPORT_JSON"])
used_mock = False

if report.get("status") != "regression" and dry_run:
    with tempfile.TemporaryDirectory() as tmp_dir:
        jsonl_dir = Path(tmp_dir)
        today = date.today().isoformat()
        previous_rows = [
            build_mock_row("2026-04-18T00:00:00+00:00", "2026-04-18", "MQ-017", "capability_reuse_rate", True, 100.0, True),
            build_mock_row("2026-04-18T00:00:00+00:00", "2026-04-18", "MQ-005", "owner_delegation_burden", True, 0.0, True),
        ]
        current_rows = [
            build_mock_row("2026-04-19T00:00:00+00:00", today, "MQ-017", "capability_reuse_rate", False, 66.67, False),
            build_mock_row("2026-04-19T00:00:00+00:00", today, "MQ-005", "owner_delegation_burden", False, 25.0, False),
        ]
        write_jsonl(jsonl_dir / "2026-04-18.jsonl", previous_rows)
        write_jsonl(jsonl_dir / "2026-04-19.jsonl", current_rows)

        import subprocess

        completed = subprocess.run(
            [python_bin, str(repo_root / ".claude/evals/manager-quality/report.py"), "regression", "--jsonl-dir", str(jsonl_dir), "--json"],
            capture_output=True,
            text=True,
            check=False,
        )
        report = json.loads(completed.stdout)
        used_mock = True

if report.get("status") != "regression":
    print(json.dumps({"status": report.get("status"), "message": "no regression detected"}, ensure_ascii=False))
    raise SystemExit(0)

task_stub = report.get("task_stub", {})
task_id = task_stub.get("id", f"T-FIX-MQ-{date.today().strftime('%Y%m%d')}")
case_regressions = report.get("regressions", [])
metric_regressions = report.get("metric_regressions", [])
order_path = repo_root / ".ai" / "CODEX" / "ORDERS" / f"{task_id}.md"

allowed_paths = [
    ".claude/evals/manager-quality/",
    "scripts/eval/",
    "scripts/evolve/",
]

acceptance = [
    "- regressed case が latest run で pass に戻る",
    "- regressed metric が target を再達成する",
    "- regression report が `stable` に戻る",
]

body_lines = [
    f"# Work Order: {task_id}",
    "",
    "## Task",
    f"- ID: {task_id}",
    f"- Title: {task_stub.get('title', 'Manager Quality regression fix')}",
    "- Role: implementer",
    f"- Priority: {task_stub.get('priority', 'P0')}",
    "",
    "## Allowed Paths",
]
body_lines.extend([f"- `{path}`" for path in allowed_paths])
body_lines.extend([
    "",
    "## Context",
    "- daily-health-check で Manager Quality regression を検知したため、自動で fix task template を生成した。",
    "",
    "## Regression Inputs",
])
if case_regressions:
    for item in case_regressions:
        body_lines.append(f"- Case: `{item['case_id']}` {item['title']} [{item['metric']}] from {', '.join(item['baseline_runs'])}")
else:
    body_lines.append("- Case: none")
if metric_regressions:
    for item in metric_regressions:
        body_lines.append(f"- Metric: `{item['metric']}` previous={item.get('previous_pcts')} current={item.get('current_pct')}%")
else:
    body_lines.append("- Metric: none")

body_lines.extend([
    "",
    "## Acceptance Criteria",
])
body_lines.extend(acceptance)
body_lines.extend([
    "",
    "## Instructions",
    "1. regression を起こした case / metric の root cause を特定する",
    "2. `.claude/evals/manager-quality/report.py` または関連 runtime wiring を最小修正する",
    "3. `bash .claude/evals/manager-quality/run.sh` と `bash scripts/eval/generate-regression-report.sh` で回復を確認する",
    "4. TASKS.yaml / DECISIONS.md は編集しない",
    "",
    "## Notes",
    f"- generated_from: `{report.get('current_run_id')}`",
    f"- mock_source: `{str(used_mock).lower()}`",
    "",
])

content = "\n".join(body_lines) + "\n"

if dry_run:
    print(json.dumps({
        "status": "dry_run",
        "task_id": task_id,
        "used_mock": used_mock,
        "path": str(order_path),
        "content_preview": content,
    }, ensure_ascii=False, indent=2))
else:
    order_path.parent.mkdir(parents=True, exist_ok=True)
    order_path.write_text(content, encoding="utf-8")
    print(json.dumps({
        "status": "written",
        "task_id": task_id,
        "used_mock": used_mock,
        "path": str(order_path),
    }, ensure_ascii=False, indent=2))
PY
