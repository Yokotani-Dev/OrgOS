#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$ROOT_DIR/scripts/security/common.sh"

if ! command -v python3 >/dev/null 2>&1; then
  log_warn "python3 が見つからないため secret scan をスキップします"
  exit 0
fi

python3 - "$ROOT_DIR" <<'PY'
from __future__ import annotations

import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
ai_dir = root / ".ai"
if not ai_dir.exists():
    print("[WARN] .ai ディレクトリが見つからないため secret scan をスキップします", file=sys.stderr)
    sys.exit(0)

scan_files = []
for path in sorted(ai_dir.rglob("*")):
    if not path.is_file():
        continue
    if path.suffix.lower() not in {".yaml", ".yml", ".md"}:
        continue
    if any(part in {"_archive"} for part in path.parts):
        continue
    scan_files.append(path)

field_pattern = re.compile(r"^\s*(api_key|password|token|secret)\s*:\s*(.+?)\s*$", re.IGNORECASE)
inline_patterns = [
    ("OpenAI/Stripe style secret", re.compile(r"\b(?:sk|pk)_(?:live|test)_[A-Za-z0-9]{8,}\b")),
    ("Slack bot token", re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}\b")),
    ("GitHub token", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}\b")),
    ("GitHub fine-grained token", re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}\b")),
    ("AWS access key", re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b")),
    ("Stripe restricted key", re.compile(r"\brk_(?:live|test)_[A-Za-z0-9]{8,}\b")),
]
field_value_patterns = [
    re.compile(r"^(?:['\"])?(?:sk|pk)_(?:live|test)_[A-Za-z0-9]{8,}(?:['\"])?$"),
    re.compile(r"^(?:['\"])?xox[baprs]-[A-Za-z0-9-]{10,}(?:['\"])?$"),
    re.compile(r"^(?:['\"])?gh[pousr]_[A-Za-z0-9]{20,}(?:['\"])?$"),
    re.compile(r"^(?:['\"])?github_pat_[A-Za-z0-9_]{20,}(?:['\"])?$"),
    re.compile(r"^(?:['\"])?(?:AKIA|ASIA)[A-Z0-9]{16}(?:['\"])?$"),
    re.compile(r"^(?:['\"])?rk_(?:live|test)_[A-Za-z0-9]{8,}(?:['\"])?$"),
]

placeholder_tokens = {
    "",
    "xxx",
    "yyy",
    "zzz",
    "dummy",
    "dummytoken",
    "placeholder",
    "changeme",
    "set_me",
    "<set_me>",
    "<redacted>",
    "[redacted]",
    "redacted",
    "example",
    "example.com",
    "example@example.com",
    "env://var_name",
    "keychain://service/name",
    "1password://vault/item",
    "sops://path/to/secret",
    "env://supabase_access_token",
}

safe_substrings = (
    "example.com",
    "example.org",
    "example.net",
    "<set_me>",
    "[redacted",
    "redacted",
    "dummy",
    "placeholder",
    "changeme",
    "env://",
    "1password://",
    "keychain://",
    "sops://",
    "vault://",
)

def normalize_value(value: str) -> str:
    value = value.split(" #", 1)[0].strip()
    value = value.strip("'\"")
    return value.strip()

def is_placeholder(value: str) -> bool:
    lowered = normalize_value(value).lower()
    compact = re.sub(r"[\s_\-]+", "", lowered)
    if lowered in placeholder_tokens or compact in {"xxx", "yyy", "zzz", "setme"}:
        return True
    return any(token in lowered for token in safe_substrings)

def likely_real_secret_field(name: str, value: str) -> bool:
    normalized = normalize_value(value)
    if not normalized or is_placeholder(normalized):
        return False
    if normalized.lower() in {"true", "false", "null", "none"}:
        return False
    if len(normalized) < 8:
        return False
    if any(pattern.search(normalized) for pattern in field_value_patterns):
        return True
    if name.lower() == "api_key":
        return True
    return bool(re.search(r"[A-Za-z]", normalized) and re.search(r"\d", normalized))

findings: list[tuple[pathlib.Path, int, str, str]] = []

for path in scan_files:
    for lineno, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw_line.rstrip()
        field_match = field_pattern.match(line)
        if field_match:
            field_name, field_value = field_match.groups()
            if likely_real_secret_field(field_name, field_value):
                findings.append((path, lineno, "secret-like field value", line))
                continue

        for label, pattern in inline_patterns:
            match = pattern.search(line)
            if not match:
                continue
            token = match.group(0)
            if is_placeholder(token):
                continue
            findings.append((path, lineno, label, line))
            break

if findings:
    print("[ERROR] plain secret candidate detected in .ai files", file=sys.stderr)
    for path, lineno, label, line in findings:
        rel = path.relative_to(root)
        print(f"{rel}:{lineno}: {label}: {line}", file=sys.stderr)
    sys.exit(1)

print("[OK] no plain secret candidates detected")
PY
