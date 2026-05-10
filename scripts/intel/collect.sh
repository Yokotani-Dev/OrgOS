#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
CONFIG_FILE="${INTEL_CONFIG:-$REPO_ROOT/.ai/INTELLIGENCE/config.yaml}"
RAW_DIR="${INTEL_RAW_DIR:-$REPO_ROOT/.ai/INTELLIGENCE/raw}"
RUN_DATE="${INTEL_RUN_DATE:-$(date -u +%F)}"
FETCH_BIN="${INTEL_FETCH_BIN:-curl}"
MAX_TIME="${INTEL_MAX_TIME:-20}"

log_json() {
  local level="$1"
  local event="$2"
  local source_id="$3"
  local message="$4"
  python3 - "$level" "$event" "$source_id" "$message" <<'PY'
from __future__ import annotations

import datetime as dt
import json
import sys

level, event, source_id, message = sys.argv[1:5]
payload = {
    "ts": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "level": level,
    "event": event,
    "source_id": source_id,
    "message": message,
}
print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), file=sys.stderr)
PY
}

ttl_seconds() {
  case "$1" in
    *h) echo "$((${1%h} * 3600))" ;;
    *d) echo "$((${1%d} * 86400))" ;;
    *m) echo "$((${1%m} * 60))" ;;
    ''|*[!0-9]*) echo "86400" ;;
    *) echo "$1" ;;
  esac
}

source_rows() {
  python3 - "$CONFIG_FILE" <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path

config_path = Path(sys.argv[1])

def clean(value: str) -> str:
    value = value.strip()
    if value and value[0] in {'"', "'"} and value[-1:] == value[0]:
        value = value[1:-1]
    return value

def parse_sources_without_yaml(text: str) -> list[dict[str, str]]:
    sources: list[dict[str, str]] = []
    current: dict[str, str] | None = None
    in_sources = False

    for raw_line in text.splitlines():
        line = raw_line.split("#", 1)[0].rstrip()
        stripped = line.strip()
        if not stripped:
            continue
        if not in_sources:
            if stripped == "sources:":
                in_sources = True
            continue
        if not raw_line.startswith((" ", "\t", "-")) and stripped != "sources:":
            break
        if stripped.startswith("- "):
            if current:
                sources.append(current)
            current = {}
            remainder = stripped[2:].strip()
            if ":" in remainder:
                key, value = remainder.split(":", 1)
                current[clean(key)] = clean(value)
            continue
        if current is not None and ":" in stripped:
            key, value = stripped.split(":", 1)
            current[clean(key)] = clean(value)

    if current:
        sources.append(current)
    return sources

try:
    import yaml  # type: ignore
except Exception:
    yaml = None

if not config_path.exists():
    raise SystemExit(f"missing config: {config_path}")

text = config_path.read_text(encoding="utf-8")
if yaml is not None:
    doc = yaml.safe_load(text) or {}
    sources = doc.get("sources", []) if isinstance(doc, dict) else []
else:
    sources = parse_sources_without_yaml(text)

if isinstance(sources, dict):
    flattened = []
    for group in sources.values():
        if isinstance(group, list):
            flattened.extend(group)
    sources = flattened

for source in sources:
    if not isinstance(source, dict):
        continue
    source_id = str(source.get("id") or "").strip()
    source_type = str(source.get("type") or "rss").strip()
    url = str(source.get("url") or "").strip()
    cadence = str(source.get("fetch_cadence") or "weekly").strip()
    ttl = str(source.get("cache_ttl") or "24h").strip()
    if not source_id or not url:
        continue
    if not re.fullmatch(r"[A-Za-z0-9._-]+", source_id):
        continue
    print("\t".join([source_id, source_type, url, cadence, ttl]))
PY
}

mkdir -p "$RAW_DIR"

if [[ ! -f "$CONFIG_FILE" ]]; then
  log_json "error" "config_missing" "-" "config file not found: $CONFIG_FILE"
  exit 0
fi

rows_file="$(mktemp "${TMPDIR:-/tmp}/orgos-intel-sources.XXXXXX")"
if ! source_rows >"$rows_file"; then
  log_json "error" "config_parse_failed" "-" "unable to parse source config"
  rm -f "$rows_file"
  exit 0
fi

if [[ ! -s "$rows_file" ]]; then
  log_json "warn" "no_sources" "-" "no fetchable sources found"
  rm -f "$rows_file"
  exit 0
fi

while IFS=$'\t' read -r source_id source_type url cadence ttl; do
  if [[ "$cadence" != "weekly" ]]; then
    log_json "info" "source_skipped" "$source_id" "unsupported cadence: $cadence"
    continue
  fi

  extension="xml"
  if [[ "$source_type" == "json" || "$url" == *.json ]]; then
    extension="json"
  fi

  source_dir="$RAW_DIR/$source_id"
  output_file="$source_dir/$RUN_DATE.$extension"
  mkdir -p "$source_dir"

  ttl_s="$(ttl_seconds "$ttl")"
  if [[ -s "$output_file" ]]; then
    now_epoch="$(date -u +%s)"
    file_epoch="$(stat -f %m "$output_file" 2>/dev/null || stat -c %Y "$output_file" 2>/dev/null || echo 0)"
    age_s="$((now_epoch - file_epoch))"
    if [[ "$age_s" -lt "$ttl_s" ]]; then
      log_json "info" "cache_hit" "$source_id" "using cached raw file: $output_file"
      continue
    fi
  fi

  tmp_file="$(mktemp "${TMPDIR:-/tmp}/orgos-intel-fetch.XXXXXX")"
  if "$FETCH_BIN" --fail --location --silent --show-error --max-time "$MAX_TIME" "$url" >"$tmp_file" 2>/dev/null; then
    if [[ -s "$tmp_file" ]]; then
      mv "$tmp_file" "$output_file"
      log_json "info" "fetch_ok" "$source_id" "saved raw source to $output_file"
    else
      rm -f "$tmp_file"
      log_json "warn" "fetch_empty" "$source_id" "fetch returned empty body; skipped"
    fi
  else
    rm -f "$tmp_file"
    log_json "warn" "fetch_failed" "$source_id" "network or HTTP failure; skipped"
  fi
done <"$rows_file"

rm -f "$rows_file"
log_json "info" "collect_complete" "-" "collection run finished"
exit 0
