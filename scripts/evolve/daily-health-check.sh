#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
RUN_DATE="${RUN_DATE:-$(date +%F)}"
RUN_ID="${RUN_ID:-daily-health-$RUN_DATE}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/.ai/METRICS/daily-health}"
REPORT_PATH="$OUTPUT_DIR/$RUN_DATE.md"
JSONL_PATH="$OUTPUT_DIR/runs.jsonl"
EVOLVE_LOG_PATH="${EVOLVE_LOG_PATH:-$REPO_ROOT/.ai/EVOLVE_LOG.md}"
MQ_CHECK="$REPO_ROOT/.claude/evals/manager-quality/daily-check.sh"

mkdir -p "$OUTPUT_DIR"

set +e
mq_output="$("$MQ_CHECK")"
mq_exit=$?
set -e
cap_scan_stdout="$(bash "$REPO_ROOT/scripts/capabilities/scan.sh")"
normalize_json="$(bash "$REPO_ROOT/scripts/memory/normalize-lint.sh" --json)"
promote_output="$(bash "$REPO_ROOT/scripts/memory/promote-lint.sh" 2>&1)"

export REPO_ROOT RUN_ID RUN_DATE REPORT_PATH JSONL_PATH EVOLVE_LOG_PATH
export MQ_OUTPUT="$mq_output"
export MQ_EXIT="$mq_exit"
export CAP_SCAN_STDOUT="$cap_scan_stdout"
export NORMALIZE_JSON="$normalize_json"
export PROMOTE_OUTPUT="$promote_output"

"$PYTHON_BIN" - <<'PY'
from __future__ import annotations

import json
import os
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import yaml


def load_yaml(path: Path) -> Any:
    if not path.exists():
        return None
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def upsert_jsonl(path: Path, run_id: str, payload: dict[str, Any]) -> None:
    rows: list[dict[str, Any]] = []
    if path.exists():
        with path.open("r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                row = json.loads(line)
                if row.get("run_id") != run_id:
                    rows.append(row)
    rows.append(payload)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as fh:
        for row in rows:
            fh.write(json.dumps(row, ensure_ascii=False) + "\n")


def ensure_log_header(path: Path) -> str:
    if path.exists():
        return path.read_text(encoding="utf-8")
    header = "# EVOLVE LOG\n\n> org-evolve の実行履歴。自動生成・自動追記。\n\n---\n"
    path.write_text(header, encoding="utf-8")
    return header


def dedupe_log_entries(path: Path, run_id: str) -> str:
    content = ensure_log_header(path)
    marker = f"| run_id | `{run_id}` |"
    if marker not in content:
        return content

    parts = content.split("\n## ")
    if len(parts) == 1:
        return content

    head = parts[0]
    kept_sections: list[str] = []
    seen = False
    for section in parts[1:]:
        rendered = "## " + section
        if marker in rendered:
            if seen:
                continue
            seen = True
        kept_sections.append(rendered.rstrip())

    normalized = head.rstrip() + "\n\n" + "\n\n".join(kept_sections) + "\n"
    path.write_text(normalized, encoding="utf-8")
    return normalized


def append_log_if_missing(path: Path, run_id: str, entry: str) -> None:
    content = dedupe_log_entries(path, run_id)
    marker = f"| run_id | `{run_id}` |"
    if marker in content:
        return
    with path.open("a", encoding="utf-8") as fh:
        if not content.endswith("\n"):
            fh.write("\n")
        fh.write("\n")
        fh.write(entry)
        if not entry.endswith("\n"):
            fh.write("\n")


repo_root = Path(os.environ["REPO_ROOT"])
run_id = os.environ["RUN_ID"]
run_date = os.environ["RUN_DATE"]
report_path = Path(os.environ["REPORT_PATH"])
jsonl_path = Path(os.environ["JSONL_PATH"])
evolve_log_path = Path(os.environ["EVOLVE_LOG_PATH"])

mq_payload = json.loads(os.environ["MQ_OUTPUT"])
mq_exit = int(os.environ["MQ_EXIT"])
normalize_payload = json.loads(os.environ["NORMALIZE_JSON"])
promote_output = os.environ["PROMOTE_OUTPUT"]

capabilities_doc = load_yaml(repo_root / ".ai" / "CAPABILITIES.yaml") or {}
profile_doc = load_yaml(repo_root / ".ai" / "USER_PROFILE.yaml") or {}
capabilities = capabilities_doc.get("capabilities", []) if isinstance(capabilities_doc, dict) else []
facts = profile_doc.get("facts", []) if isinstance(profile_doc, dict) else []
preferences = profile_doc.get("preferences", []) if isinstance(profile_doc, dict) else []

verified_capabilities = [
    item for item in capabilities
    if isinstance(item, dict)
    and str(item.get("auth_status", "")).lower() in {"verified", "not_required"}
]

promote_warning_count = sum(
    1
    for line in promote_output.splitlines()
    if line.lstrip().startswith("- ")
)
normalize_warning_count = len(normalize_payload.get("warnings", []))
memory_status = "ok" if normalize_warning_count == 0 and promote_warning_count == 0 else "warn"

eval_summary = mq_payload.get("eval", {})
regression = mq_payload.get("regression", {})
regressions = regression.get("regressions", []) or []
metric_regressions = regression.get("metric_regressions", []) or []
regression_count = len(regressions) + len(metric_regressions)

metrics = eval_summary.get("metrics", {})
improved_metrics = [
    metric_id for metric_id, summary in metrics.items()
    if isinstance(summary, dict) and summary.get("target_met")
]
regressed_metrics = [item.get("metric") for item in metric_regressions if item.get("metric")]
learned_success = []
if improved_metrics:
    learned_success.append("target_met metrics は daily baseline として維持対象")
if verified_capabilities:
    learned_success.append("capability scan を先に実行すると reuse judge の前提が揃う")
learned_failure = []
if regressions or metric_regressions:
    learned_failure.append("regression 発生時は日次で fix task を切り出し、週次 org-evolve に持ち越さない")
if normalize_warning_count or promote_warning_count:
    learned_failure.append("memory lint warn は将来の context miss/trace 劣化の先行指標として扱う")
next_candidates = []
if regressions:
    next_candidates.append("regressed case の fix task 着手")
if metric_regressions:
    next_candidates.append("未達 metric の rubric / data wiring 見直し")
if not next_candidates:
    next_candidates.append("前日との差分学習を org-evolve external scan 入力へ供給")

digest = {
    "run_id": run_id,
    "run_date": run_date,
    "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
    "manager_quality": {
        "passed": eval_summary.get("passed"),
        "cases": eval_summary.get("cases"),
        "failed": eval_summary.get("failed"),
        "critical_failure": eval_summary.get("critical_failure"),
        "exit_code": mq_exit,
    },
    "capabilities": {
        "detected": len(capabilities),
        "auth_verified": len(verified_capabilities),
    },
    "memory": {
        "facts": len(facts),
        "preferences": len(preferences),
        "normalize_warnings": normalize_warning_count,
        "promote_warnings": promote_warning_count,
        "status": memory_status,
    },
    "recent_regressions": {
        "count": regression_count,
        "status": regression.get("status"),
    },
}
upsert_jsonl(jsonl_path, run_id, digest)

lines = [
    "# Daily Health Report",
    "",
    f"- run_id: `{run_id}`",
    f"- run_date: `{run_date}`",
    f"- generated_at: `{digest['generated_at']}`",
    "",
    "## Digest",
    f"- Manager Quality: {eval_summary.get('passed', 0)}/{eval_summary.get('cases', 0)} pass",
    f"- Capabilities: {len(capabilities)} detected ({len(verified_capabilities)} auth_verified)",
    f"- Memory: {len(facts)} facts, {len(preferences)} preferences",
    f"- Recent regressions: {regression_count} detected",
    "",
    "## Manager Quality",
    f"- exit_code: `{mq_exit}`",
    f"- regression_status: `{regression.get('status', 'unknown')}`",
]

for metric_id, summary in sorted(metrics.items()):
    current = summary.get("current_pct")
    lines.append(
        f"- `{metric_id}`: {current if current is not None else 'n/a'}% / target `{summary.get('target')}` / {'pass' if summary.get('target_met') else 'fail'}"
    )

lines.extend([
    "",
    "## Regressions",
])
if regressions:
    for item in regressions:
        lines.append(f"- case `{item['case_id']}`: {item['title']} [{item['metric']}]")
else:
    lines.append("- case regressions: none")
if metric_regressions:
    for item in metric_regressions:
        lines.append(f"- metric `{item['metric']}`: current {item.get('current_pct')}%")
else:
    lines.append("- metric regressions: none")

lines.extend([
    "",
    "## Capabilities",
    f"- scan_output: `{os.environ['CAP_SCAN_STDOUT'].strip()}`",
    f"- manifest_path: `{repo_root / '.ai' / 'CAPABILITIES.yaml'}`",
    "",
    "## Memory",
    f"- normalize_lint: `{normalize_payload.get('status', 'unknown')}` ({normalize_warning_count} warnings)",
    f"- promote_lint: `{memory_status}` ({promote_warning_count} warnings)",
])
for warning in normalize_payload.get("warnings", [])[:10]:
    lines.append(f"- normalize warning: {warning.get('message', warning.get('kind', 'warning'))}")
if promote_output.strip():
    for line in promote_output.splitlines():
        if line.startswith("[") or line.lstrip().startswith("- "):
            lines.append(f"- promote output: {line}")

lines.extend([
    "",
    "## Learning Trace",
    f"- improved_metrics: {', '.join(improved_metrics) if improved_metrics else 'none'}",
    f"- regressed_metrics: {', '.join(regressed_metrics) if regressed_metrics else 'none'}",
    f"- learned_success: {'; '.join(learned_success) if learned_success else 'none'}",
    f"- learned_failure: {'; '.join(learned_failure) if learned_failure else 'none'}",
    f"- next_candidates: {'; '.join(next_candidates)}",
])

report_path.parent.mkdir(parents=True, exist_ok=True)
report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

existing = ensure_log_header(evolve_log_path)
entry_numbers = [int(num) for num in re.findall(r"## EVOLVE-(\d+):", existing)]
next_num = max(entry_numbers, default=0) + 1
entry = "\n".join([
    f"## EVOLVE-{next_num:03d}: daily-health-check ({run_date})",
    "",
    "| 項目 | 値 |",
    "|------|-----|",
    "| カテゴリ | daily-health |",
    "| 対象ファイル | .claude/evals/manager-quality/daily-check.sh, scripts/evolve/daily-health-check.sh |",
    f"| メトリクス（before） | recent regressions: {regression_count} |",
    f"| メトリクス（after） | manager quality: {eval_summary.get('passed', 0)}/{eval_summary.get('cases', 0)} pass |",
    "| 結果 | KEEP |",
    "| コミット | n/a |",
    f"| Eval | {'pass' if not eval_summary.get('critical_failure') else 'fail'} |",
    "| 出典 | internal |",
    f"| run_id | `{run_id}` |",
    "",
    "### 学習トレース",
    f"- 改善: {', '.join(improved_metrics) if improved_metrics else 'none'}",
    f"- 退行: {', '.join(regressed_metrics) if regressed_metrics else 'none'}",
    f"- 学習内容: {'; '.join(filter(None, learned_success + learned_failure)) if (learned_success or learned_failure) else 'none'}",
    f"- 次の改善候補: {'; '.join(next_candidates)}",
    "",
])
append_log_if_missing(evolve_log_path, run_id, entry)

print(report_path)
PY

if [[ $mq_exit -eq 2 ]]; then
  exit 2
fi
exit "$mq_exit"
