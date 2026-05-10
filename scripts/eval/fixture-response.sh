#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s <fixture_file>\n' "${0##*/}" >&2
}

if [[ $# -ne 1 ]]; then
  usage
  exit 64
fi

FIXTURE_FILE="$1"

if [[ ! -f "$FIXTURE_FILE" ]]; then
  printf 'fixture-response: fixture file not found: %s\n' "$FIXTURE_FILE" >&2
  exit 66
fi

PYTHON_BIN="${PYTHON_BIN:-python3}"

"$PYTHON_BIN" - "$FIXTURE_FILE" <<'PY'
import hashlib
import json
import re
import sys
from pathlib import Path

import yaml

fixture_path = Path(sys.argv[1])
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

request = data.get("request")
expected_pattern = data.get("expected_response_pattern")
actual = data.get("actual_response_to_evaluate")
missing = [
    name
    for name, value in (
        ("request", request),
        ("expected_response_pattern", expected_pattern),
        ("actual_response_to_evaluate", actual),
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

try:
    expected_re = re.compile(expected_pattern, re.IGNORECASE | re.MULTILINE | re.DOTALL)
except re.error as exc:
    emit(
        {
            "status": "invalid_fixture",
            "fixture_file": str(fixture_path),
            "measured": False,
            "fallback_used": False,
            "reason": f"invalid expected_response_pattern regex: {exc}",
        },
        65,
    )

forbidden_patterns = data.get("forbidden_patterns", [])
if forbidden_patterns is None:
    forbidden_patterns = []
if not isinstance(forbidden_patterns, list):
    emit(
        {
            "status": "invalid_fixture",
            "fixture_file": str(fixture_path),
            "measured": False,
            "fallback_used": False,
            "reason": "forbidden_patterns must be a list when present",
        },
        65,
    )

forbidden_hits = []
for pattern in forbidden_patterns:
    if not isinstance(pattern, str) or not pattern.strip():
        emit(
            {
                "status": "invalid_fixture",
                "fixture_file": str(fixture_path),
                "measured": False,
                "fallback_used": False,
                "reason": "forbidden_patterns entries must be non-empty strings",
            },
            65,
        )
    try:
        forbidden_re = re.compile(pattern, re.IGNORECASE | re.MULTILINE | re.DOTALL)
    except re.error as exc:
        emit(
            {
                "status": "invalid_fixture",
                "fixture_file": str(fixture_path),
                "measured": False,
                "fallback_used": False,
                "reason": f"invalid forbidden pattern regex: {exc}",
            },
            65,
        )
    if forbidden_re.search(actual):
        forbidden_hits.append(pattern)

match = expected_re.search(actual)
passed = bool(match) and not forbidden_hits
reason = "actual response matched expected pattern"
if not match:
    reason = "actual response did not match expected pattern"
elif forbidden_hits:
    reason = "actual response matched forbidden pattern(s)"

emit(
    {
        "status": "passed" if passed else "failed",
        "fixture_file": str(fixture_path),
        "fixture_id": data.get("id", fixture_path.stem),
        "request_hash": hashlib.sha256(request.encode("utf-8")).hexdigest()[:16],
        "measured": True,
        "fallback_used": False,
        "expected_response_pattern": expected_pattern,
        "matched": bool(match),
        "forbidden_hits": forbidden_hits,
        "reason": reason,
        "reasoning_trace": {
            "actual_length": len(actual),
            "match_excerpt": match.group(0)[:160] if match else "",
        },
    },
    0 if passed else 1,
)
PY
