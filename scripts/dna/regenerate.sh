#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DNA_FILE="$ROOT_DIR/.ai/ORG_DNA.yaml"
HISTORY_FILE="$ROOT_DIR/.ai/DNA_HISTORY.yaml"
MANIFEST_FILE="$ROOT_DIR/.orgos-manifest.yaml"
GOALS_FILE="$ROOT_DIR/.ai/GOALS.yaml"
SCHEMA_FILE="$ROOT_DIR/.claude/schemas/org-dna.yaml"

DRY_RUN=0
BUMP_KIND=""

log_json() {
  local level="$1"
  local event="$2"
  local message="$3"
  printf '{"level":"%s","event":"%s","message":"%s"}\n' "$level" "$event" "$message" >&2
}

usage() {
  cat <<'USAGE'
Usage:
  scripts/dna/regenerate.sh [--dry-run] [--bump-version patch|minor|major]

Reads .ai/ORG_DNA.yaml, rescans OrgOS component directories, and updates DNA.
--dry-run prints added / removed / modified components without writing files.
--bump-version increments the DNA semver before writing.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --bump-version)
      if [[ $# -lt 2 ]]; then
        log_json error missing_bump_value "--bump-version requires patch, minor, or major"
        exit 2
      fi
      BUMP_KIND="$2"
      case "$BUMP_KIND" in
        patch|minor|major) ;;
        *)
          log_json error invalid_bump_value "bump value must be patch, minor, or major"
          exit 2
          ;;
      esac
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log_json error unknown_argument "unknown argument: $1"
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -f "$MANIFEST_FILE" ]]; then
  log_json error missing_manifest ".orgos-manifest.yaml is required for classification"
  exit 1
fi

if [[ ! -f "$GOALS_FILE" ]]; then
  log_json error missing_goals ".ai/GOALS.yaml is required for metadata"
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  log_json error missing_python "python3 is required"
  exit 1
fi

python3 - "$ROOT_DIR" "$DNA_FILE" "$HISTORY_FILE" "$DRY_RUN" "${BUMP_KIND:-}" <<'PY'
from __future__ import annotations

import copy
import difflib
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

try:
    import yaml
except Exception as exc:
    print(json.dumps({
        "level": "error",
        "event": "missing_pyyaml",
        "message": f"PyYAML is required: {exc}",
    }), file=sys.stderr)
    sys.exit(1)

ROOT = Path(sys.argv[1])
DNA_FILE = Path(sys.argv[2])
HISTORY_FILE = Path(sys.argv[3])
DRY_RUN = sys.argv[4] == "1"
BUMP_KIND = sys.argv[5] or None
DNA_VERSION_DEFAULT = "0.1.0"

SCAN_TARGETS = {
    "rules": Path(".claude/rules"),
    "agents": Path(".claude/agents"),
    "skills": Path(".claude/skills"),
    "capabilities": Path(".ai/CAPABILITIES.example.yaml"),
    "schemas": Path(".claude/schemas"),
    "commands": Path(".claude/commands"),
}


class LiteralString(str):
    pass


def _literal_representer(dumper, data):
    return dumper.represent_scalar("tag:yaml.org,2002:str", data, style="|")


yaml.SafeDumper.add_representer(LiteralString, _literal_representer)


def log(level: str, event: str, message: str, **fields):
    payload = {"level": level, "event": event, "message": message}
    payload.update(fields)
    print(json.dumps(payload, ensure_ascii=False), file=sys.stderr)


def load_yaml(path: Path, default):
    if not path.exists():
        return default
    with path.open("r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh)
    return data if data is not None else default


def dump_yaml(data) -> str:
    return yaml.safe_dump(
        data,
        allow_unicode=True,
        sort_keys=False,
        default_flow_style=False,
        width=1000,
    )


def read_manifest_sets():
    manifest = load_yaml(ROOT / ".orgos-manifest.yaml", {})
    publish = set(manifest.get("publish") or [])
    core = set(manifest.get("core") or [])
    preserve = set(manifest.get("preserve") or [])
    template_sources = set()
    for item in manifest.get("templates") or []:
        if isinstance(item, dict) and item.get("source"):
            template_sources.add(item["source"])
    return publish | core | template_sources, preserve


def metadata_from_goals():
    goals = load_yaml(ROOT / ".ai/GOALS.yaml", {})
    vision = goals.get("vision") or {}
    milestones = []
    for milestone in goals.get("milestones") or []:
        if milestone.get("status") in {"active", "achieved"}:
            milestones.append(milestone.get("id"))
    return {
        "project_name": "OrgOS",
        "vision_ref": vision.get("id") or "V-ORGOS",
        "primary_milestones": [m for m in milestones if m] or ["M-PHASE-2"],
        "source_manifest": ".orgos-manifest.yaml",
        "notes": "Manifest remains read-only in T-OS-323; this DNA is the source for future export views.",
    }


def sha256_for(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return "sha256:" + digest.hexdigest()


def component_id(kind: str, rel: str) -> str:
    stem = rel
    for prefix in [".claude/rules/", ".claude/agents/", ".claude/skills/", ".claude/schemas/", ".claude/commands/", ".ai/"]:
        if stem.startswith(prefix):
            stem = stem[len(prefix):]
            break
    stem = re.sub(r"\.(md|ya?ml|json|sh)$", "", stem)
    return f"{kind}:{stem}"


def version_for_existing(current, kind: str, rel: str, fallback: str) -> str:
    for item in (current.get("components") or {}).get(kind) or []:
        if item.get("path") == rel:
            return item.get("version") or fallback
    return fallback


def classification_for(rel: str, managed_paths: set[str], owner_paths: set[str]) -> str:
    if rel == ".claude/schemas/org-dna.yaml":
        return "generated"
    if rel in owner_paths:
        return "owner-edited"
    if rel in managed_paths:
        return "managed"
    return "managed"


def scan_components(current, version: str):
    managed_paths, owner_paths = read_manifest_sets()
    components = {key: [] for key in SCAN_TARGETS}

    for kind, target in SCAN_TARGETS.items():
        absolute = ROOT / target
        paths = []
        if absolute.is_file():
            paths = [absolute]
        elif absolute.is_dir():
            paths = [p for p in absolute.rglob("*") if p.is_file()]
        else:
            log("warning", "missing_scan_target", f"scan target missing: {target}")
            continue

        for path in sorted(paths, key=lambda p: str(p.relative_to(ROOT))):
            rel = str(path.relative_to(ROOT))
            components[kind].append({
                "id": component_id(kind, rel),
                "path": rel,
                "version": version_for_existing(current, kind, rel, version),
                "classification": classification_for(rel, managed_paths, owner_paths),
                "checksum": sha256_for(path),
                "depends_on": [],
            })
    return components


def bump_version(version: str, kind: str | None) -> str:
    if not kind:
        return version
    match = re.match(r"^(\d+)\.(\d+)\.(\d+)", version)
    if not match:
        raise ValueError(f"cannot bump non-semver version: {version}")
    major, minor, patch = map(int, match.groups())
    if kind == "major":
        return f"{major + 1}.0.0"
    if kind == "minor":
        return f"{major}.{minor + 1}.0"
    if kind == "patch":
        return f"{major}.{minor}.{patch + 1}"
    raise ValueError(f"unsupported bump kind: {kind}")


def index_components(dna):
    indexed = {}
    for kind, items in (dna.get("components") or {}).items():
        for item in items or []:
            indexed[item["path"]] = {
                "kind": kind,
                "id": item.get("id"),
                "checksum": item.get("checksum"),
                "version": item.get("version"),
                "classification": item.get("classification"),
                "depends_on": item.get("depends_on") or [],
            }
    return indexed


def diff_components(before, after):
    before_i = index_components(before)
    after_i = index_components(after)
    added = sorted(after_i.keys() - before_i.keys())
    removed = sorted(before_i.keys() - after_i.keys())
    modified = []
    for path in sorted(before_i.keys() & after_i.keys()):
        if before_i[path] != after_i[path]:
            modified.append(path)
    return added, removed, modified


def diff_text(before, after):
    added, removed, modified = diff_components(before, after)
    lines = [
        "added:",
        *[f"  - {path}" for path in added],
        "removed:",
        *[f"  - {path}" for path in removed],
        "modified:",
        *[f"  - {path}" for path in modified],
    ]
    if not added and not removed and not modified:
        lines.append("no changes")
    return "\n".join(lines) + "\n"


def history_entry(dna, reason: str):
    return {
        "version": dna.get("version"),
        "recorded_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "reason": reason,
        "component_count": sum(len(v or []) for v in (dna.get("components") or {}).values()),
        "snapshot": copy.deepcopy(dna),
    }


def append_history(history, dna, reason: str):
    entries = history.setdefault("history", [])
    version = dna.get("version")
    if any(entry.get("version") == version for entry in entries):
        return False
    entries.append(history_entry(dna, reason))
    return True


def upsert_history(history, dna, reason: str):
    entries = history.setdefault("history", [])
    version = dna.get("version")
    replacement = history_entry(dna, reason)
    for idx, entry in enumerate(entries):
        if entry.get("version") == version:
            entries[idx] = replacement
            return "updated"
    entries.append(replacement)
    return "appended"


def atomic_write(path: Path, text: str):
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, path)


current = load_yaml(DNA_FILE, {})
current_version = current.get("version") or DNA_VERSION_DEFAULT
next_version = bump_version(current_version, BUMP_KIND)
now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

next_dna = {
    "version": next_version,
    "generated_at": now,
    "generator": "codex",
    "metadata": metadata_from_goals(),
    "components": scan_components(current, next_version),
}

if current:
    # generated_at is metadata, not a component change. Keep it stable on no-op updates.
    added, removed, modified = diff_components(current, next_dna)
    if not added and not removed and not modified and current.get("version") == next_dna.get("version"):
        next_dna["generated_at"] = current.get("generated_at", now)
else:
    added, removed, modified = [], [], []

if DRY_RUN:
    print(diff_text(current, next_dna), end="")
    sys.exit(0)

history = load_yaml(HISTORY_FILE, {"schema_version": "1.0", "history": []})
if current:
    if added or removed or modified or current.get("version") != next_dna.get("version"):
        append_history(history, current, "pre-update snapshot")
else:
    upsert_history(history, next_dna, "initial DNA snapshot")

upsert_history(history, next_dna, "current DNA snapshot")

atomic_write(DNA_FILE, dump_yaml(next_dna))
atomic_write(HISTORY_FILE, dump_yaml(history))

log(
    "info",
    "dna_regenerated",
    "ORG_DNA.yaml regenerated",
    version=next_version,
    component_count=sum(len(v) for v in next_dna["components"].values()),
    added=len(added),
    removed=len(removed),
    modified=len(modified),
)
PY
