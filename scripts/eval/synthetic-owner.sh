#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s <scenario_file>\n' "${0##*/}" >&2
}

if [[ $# -ne 1 ]]; then
  usage
  exit 64
fi

SCENARIO_FILE="$1"

if [[ ! -f "$SCENARIO_FILE" ]]; then
  printf 'synthetic-owner: scenario file not found: %s\n' "$SCENARIO_FILE" >&2
  exit 66
fi

PYTHON_BIN="${PYTHON_BIN:-python3}"

"$PYTHON_BIN" - "$SCENARIO_FILE" <<'PY'
import hashlib
import json
import re
import sys
from pathlib import Path

import yaml

fixture_path = Path(sys.argv[1])
ALLOWED_VERDICTS = {"approve", "reject", "needs_more_context"}
SECRET_PATTERNS = (
    re.compile(r"sk-[A-Za-z0-9_-]{16,}"),
    re.compile(r"gh[pousr]_[A-Za-z0-9_]{20,}"),
    re.compile(r"AKIA[0-9A-Z]{16}"),
    re.compile(r"(?i)(api[_-]?key|secret|password|token)\s*[:=]\s*['\"]?[A-Za-z0-9_./+=-]{12,}"),
)


def emit(payload, exit_code):
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    sys.exit(exit_code)


def walk_strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for item in value.values():
            yield from walk_strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from walk_strings(item)


try:
    raw = fixture_path.read_text(encoding="utf-8")
    data = yaml.safe_load(raw)
except yaml.YAMLError as exc:
    emit(
        {
            "status": "invalid_fixture",
            "fixture_file": str(fixture_path),
            "measured": False,
            "fallback_used": False,
            "reason": f"YAML parse error: {exc}",
        },
        65,
    )

if not isinstance(data, dict):
    emit(
        {
            "status": "invalid_fixture",
            "fixture_file": str(fixture_path),
            "measured": False,
            "fallback_used": False,
            "reason": "fixture root must be a mapping",
        },
        65,
    )

secret_hits = []
for text in walk_strings(data):
    for pattern in SECRET_PATTERNS:
        if pattern.search(text):
            secret_hits.append(pattern.pattern)
            break
if secret_hits:
    emit(
        {
            "status": "security_failed",
            "fixture_file": str(fixture_path),
            "measured": False,
            "fallback_used": False,
            "reason": "fixture contains secret-looking material",
        },
        78,
    )

scenario = data.get("scenario")
expected = data.get("expected_verdict")
reasoning = data.get("reasoning")
signals = data.get("signals", {})

missing = [
    name
    for name, value in (
        ("scenario", scenario),
        ("expected_verdict", expected),
        ("reasoning", reasoning),
    )
    if not isinstance(value, str) or not value.strip()
]
if missing:
    emit(
        {
            "status": "invalid_fixture",
            "fixture_file": str(fixture_path),
            "measured": False,
            "fallback_used": False,
            "reason": "missing required field(s): " + ", ".join(missing),
        },
        65,
    )

if expected not in ALLOWED_VERDICTS:
    emit(
        {
            "status": "invalid_fixture",
            "fixture_file": str(fixture_path),
            "measured": False,
            "fallback_used": False,
            "reason": f"expected_verdict must be one of {sorted(ALLOWED_VERDICTS)}",
        },
        65,
    )

if not isinstance(signals, dict):
    emit(
        {
            "status": "invalid_fixture",
            "fixture_file": str(fixture_path),
            "measured": False,
            "fallback_used": False,
            "reason": "signals must be a mapping",
        },
        65,
    )

acceptance_met = bool(signals.get("acceptance_met", False))
blocker_present = bool(signals.get("blocker_present", False))
insufficient_context = bool(signals.get("insufficient_context", False))
high_risk_unmitigated = bool(signals.get("high_risk_unmitigated", False))

if insufficient_context or blocker_present:
    verdict = "needs_more_context"
    rule = "context_or_blocker_requires_owner_context"
elif high_risk_unmitigated or not acceptance_met:
    verdict = "reject"
    rule = "acceptance_or_risk_not_satisfied"
else:
    verdict = "approve"
    rule = "acceptance_met_without_unmitigated_risk"

passed = verdict == expected
emit(
    {
        "status": "passed" if passed else "failed",
        "fixture_file": str(fixture_path),
        "fixture_id": data.get("id", fixture_path.stem),
        "scenario_hash": hashlib.sha256(scenario.encode("utf-8")).hexdigest()[:16],
        "measured": True,
        "fallback_used": False,
        "expected_verdict": expected,
        "verdict": verdict,
        "rule": rule,
        "reasoning_trace": {
            "fixture_reasoning": reasoning,
            "signals": {
                "acceptance_met": acceptance_met,
                "blocker_present": blocker_present,
                "insufficient_context": insufficient_context,
                "high_risk_unmitigated": high_risk_unmitigated,
            },
        },
    },
    0 if passed else 1,
)
PY
