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
  echo "eval-scanner requires --json" >&2
  exit 1
fi

python3 - "$REPO_ROOT" <<'PY'
from __future__ import annotations

import json
import sys
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any

repo = Path(sys.argv[1])
now = datetime.now(timezone.utc).replace(microsecond=0)
detected_at = now.isoformat().replace("+00:00", "Z")


def rel(path: Path) -> str:
    try:
        return str(path.relative_to(repo))
    except ValueError:
        return str(path)


def event(**kwargs: Any) -> dict[str, Any]:
    base = {
        "detected_at": detected_at,
        "source": "eval_scanner",
        "severity": "P2",
        "confidence": 0.8,
        "novelty": "recurring",
        "target_artifacts": [],
        "evidence": [],
        "proposed_action": "update",
        "estimated_impact": "medium",
        "estimated_risk": "medium",
        "autonomy_candidate": "ask_before_execute",
        "blast_radius": "multi_file",
        "recommended_next": "Inspect the latest Manager Quality run and generate a focused fix Work Order if regression persists.",
    }
    base.update(kwargs)
    return base


events: list[dict[str, Any]] = []

mq_dir = repo / ".ai" / "_machine" / "metrics" / "manager-quality"
mq_files = sorted(p for p in mq_dir.glob("*.jsonl") if p.is_file())
if mq_files:
    latest = mq_files[-1]
    for line_no, raw in enumerate(latest.read_text(encoding="utf-8").splitlines(), start=1):
        if not raw.strip():
            continue
        try:
            row = json.loads(raw)
        except json.JSONDecodeError:
            continue
        metric = row.get("metric_snapshot") if isinstance(row.get("metric_snapshot"), dict) else {}
        target_missed = metric and metric.get("target_met") is False
        if row.get("passed") is False or target_missed:
            case_id = str(row.get("case_id") or "unknown")
            metric_id = str(row.get("metric") or metric.get("metric_id") or "unknown")
            events.append(event(
                event_type="eval_regression",
                severity=str(row.get("metric_priority") or metric.get("priority") or "P1"),
                confidence=0.95,
                target_artifacts=[{"path": rel(latest), "lines": [line_no]}],
                evidence=[{
                    "kind": "manager_quality_row",
                    "snippet": f"{case_id} metric={metric_id} passed={row.get('passed')} target_met={metric.get('target_met')}",
                }],
                recommended_next=f"Run regression analysis for {case_id} / {metric_id} and create a minimal fix task if still failing.",
            ))
else:
    events.append(event(
        event_type="eval_regression",
        severity="P2",
        confidence=0.7,
        novelty="first_seen",
        target_artifacts=[{"path": ".ai/_machine/metrics/manager-quality", "lines": []}],
        evidence=[{"kind": "missing_eval_history", "snippet": "No Manager Quality JSONL runs were found."}],
        proposed_action="add",
        estimated_risk="low",
        autonomy_candidate="execute_with_report",
        recommended_next="Run bash scripts/eval/manager-quality-runner.sh and store the first Manager Quality baseline.",
    ))

health_jsonl = repo / ".ai" / "_machine" / "metrics" / "daily-health" / "runs.jsonl"
if health_jsonl.exists():
    latest_run: dict[str, Any] | None = None
    latest_line = 0
    for line_no, raw in enumerate(health_jsonl.read_text(encoding="utf-8").splitlines(), start=1):
        if not raw.strip():
            continue
        try:
            row = json.loads(raw)
        except json.JSONDecodeError:
            continue
        latest_run = row
        latest_line = line_no
    if latest_run:
        run_date = str(latest_run.get("run_date") or "")
        try:
            age_days = (date.today() - date.fromisoformat(run_date)).days
        except ValueError:
            age_days = 999
        if age_days > 1:
            events.append(event(
                event_type="ux_drift",
                severity="P1" if age_days > 7 else "P2",
                confidence=0.9,
                target_artifacts=[{"path": rel(health_jsonl), "lines": [latest_line]}],
                evidence=[{"kind": "daily_health_age", "snippet": f"latest daily-health run_date={run_date}, age_days={age_days}"}],
                proposed_action="add",
                estimated_risk="low",
                autonomy_candidate="execute_with_report",
                recommended_next="Schedule or trigger daily-health-check so Self-Evolution has a fresh clock signal.",
            ))
else:
    events.append(event(
        event_type="ux_drift",
        severity="P1",
        confidence=0.8,
        novelty="first_seen",
        target_artifacts=[{"path": ".ai/_machine/metrics/daily-health/runs.jsonl", "lines": []}],
        evidence=[{"kind": "missing_daily_health_history", "snippet": "daily-health runs.jsonl is missing."}],
        proposed_action="add",
        estimated_risk="low",
        autonomy_candidate="execute_with_report",
        recommended_next="Run scripts/evolution/daily-health-check.sh once, then wire it to a daily trigger in a later task.",
    ))

print(json.dumps(events, ensure_ascii=False, separators=(",", ":")))
PY
