#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
JSONL_DIR="$REPO_ROOT/.ai/METRICS/manager-quality"
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --jsonl-dir)
      JSONL_DIR="$2"
      shift 2
      ;;
    --json)
      JSON_OUTPUT=true
      shift
      ;;
    *)
      echo "unknown option: $1" >&2
      exit 64
      ;;
  esac
done

python3 - "$JSONL_DIR" "$JSON_OUTPUT" <<'PY'
import json
import sys
from collections import defaultdict
from pathlib import Path

jsonl_dir = Path(sys.argv[1])
json_output = sys.argv[2].lower() == "true"

runs = {}
for path in sorted(jsonl_dir.glob("*.jsonl")):
    with path.open("r", encoding="utf-8") as fh:
        for line in fh:
            if not line.strip():
                continue
            row = json.loads(line)
            run = runs.setdefault(
                row["run_id"],
                {"run_id": row["run_id"], "run_date": row["run_date"], "rows": []},
            )
            run["rows"].append(row)

latest_by_date = {}
for run in runs.values():
    run_date = run["run_date"]
    current = latest_by_date.get(run_date)
    if current is None or run["run_id"] > current["run_id"]:
        latest_by_date[run_date] = run

series = []
for run_date in sorted(latest_by_date):
    rows = latest_by_date[run_date]["rows"]
    total_cases = len({row["case_id"] for row in rows})
    owner_requests = sum(
        1
        for row in rows
        if row.get("metric") == "owner_delegation_burden" and not row.get("passed", False)
    )
    ratio = None if total_cases == 0 else round(owner_requests / total_cases, 4)
    series.append(
        {
            "run_date": run_date,
            "run_id": latest_by_date[run_date]["run_id"],
            "owner_requests": owner_requests,
            "total_tasks": total_cases,
            "ratio": ratio,
        }
    )

window = series[-7:]
ratios = [item["ratio"] for item in window if item["ratio"] is not None]
ma7 = round(sum(ratios) / len(ratios), 4) if ratios else None
last3 = ratios[-3:]
ma3 = round(sum(last3) / len(last3), 4) if len(last3) == 3 else None

if len(ratios) < 3:
    status = "pending"
    passed = True
    reason = "Need at least 3 daily snapshots to determine a downward trend."
else:
    passed = ma3 is not None and ma7 is not None and ma3 < ma7
    status = "pass" if passed else "fail"
    reason = (
        f"3d MA {ma3:.4f} < 7d MA {ma7:.4f}"
        if passed
        else f"3d MA {ma3:.4f} >= 7d MA {ma7:.4f}"
    )

payload = {
    "status": status,
    "passed": passed,
    "reason": reason,
    "days_considered": len(ratios),
    "moving_average_3d": ma3,
    "moving_average_7d": ma7,
    "latest_ratio": ratios[-1] if ratios else None,
    "daily_series": window,
}

if json_output:
    print(json.dumps(payload, ensure_ascii=False))
else:
    print("# Owner Delegation Burden Trend")
    print("")
    print(f"- status: `{status}`")
    print(f"- reason: {reason}")
    print(
        f"- moving_average_3d: `{ma3 if ma3 is not None else 'n/a'}`"
    )
    print(
        f"- moving_average_7d: `{ma7 if ma7 is not None else 'n/a'}`"
    )
    print("")
    print("## Daily Series")
    for item in window:
        ratio_text = "n/a" if item["ratio"] is None else f"{item['ratio']:.4f}"
        print(
            f"- {item['run_date']}: owner_requests={item['owner_requests']} total_tasks={item['total_tasks']} ratio={ratio_text}"
        )

raise SystemExit(0 if passed or status == "pending" else 1)
PY
