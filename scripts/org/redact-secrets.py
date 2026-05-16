#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path


REDACTION = "[REDACTED]"


VALUE_CHARS = r"[A-Za-z0-9_./+=:@%,-]"


DIRECT_PATTERNS: list[re.Pattern[str]] = [
    re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"),
    re.compile(r"\bgh(?:p|o|u|s|r)_[A-Za-z0-9_]{30,}\b"),
    re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}\b"),
    re.compile(r"\bsk-(?:proj-)?[A-Za-z0-9_-]{20,}\b"),
    re.compile(r"\bxox(?:a|b|p|o|s|r)-[A-Za-z0-9-]{20,}\b"),
    re.compile(r"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b"),
]


PREFIX_VALUE_PATTERNS: list[re.Pattern[str]] = [
    re.compile(r"(?i)\b(Bearer\s+)" + VALUE_CHARS + r"{16,}"),
    re.compile(
        r"(?i)\b((?:aws_)?(?:secret_access_key|access_key_id)\s*[:=]\s*[\"']?)"
        + VALUE_CHARS
        + r"{12,}([\"']?)"
    ),
    re.compile(
        r"(?i)\b((?:github[_-]?)?token\s*[:=]\s*[\"']?)"
        + VALUE_CHARS
        + r"{12,}([\"']?)"
    ),
    re.compile(
        r"(?i)\b((?:api[_-]?key|auth[_-]?token|client[_-]?secret|password|passwd|pwd|secret)\s*[:=]\s*[\"']?)"
        + VALUE_CHARS
        + r"{8,}([\"']?)"
    ),
]


URL_CREDENTIAL_PATTERN = re.compile(
    r"\b([a-z][a-z0-9+.-]*://[^/\s:@]+:)[^@\s/]+(@)", re.IGNORECASE
)


def redact(text: str) -> str:
    for pattern in DIRECT_PATTERNS:
        text = pattern.sub(REDACTION, text)

    for pattern in PREFIX_VALUE_PATTERNS:
        text = pattern.sub(lambda match: f"{match.group(1)}{REDACTION}{match.group(2) if match.lastindex and match.lastindex >= 2 else ''}", text)

    return URL_CREDENTIAL_PATTERN.sub(r"\1[REDACTED]\2", text)


def read_inputs(paths: list[str]) -> str:
    if not paths:
        return sys.stdin.read()

    chunks: list[str] = []
    for raw_path in paths:
        path = Path(raw_path)
        chunks.append(path.read_text(encoding="utf-8", errors="replace"))
    return "".join(chunks)


def main() -> int:
    sys.stdout.write(redact(read_inputs(sys.argv[1:])))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
