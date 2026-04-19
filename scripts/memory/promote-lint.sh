#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$ROOT_DIR/scripts/security/common.sh"

if ! require_python_yaml_or_skip; then
  exit 0
fi

python3 - "$ROOT_DIR" <<'PY'
from __future__ import annotations

import pathlib
import re
import sys

import yaml

root = pathlib.Path(sys.argv[1])
profile_path = root / ".ai" / "USER_PROFILE.yaml"

if not profile_path.exists():
    print("[WARN] .ai/USER_PROFILE.yaml が見つからないため promote lint をスキップします", file=sys.stderr)
    sys.exit(0)

data = yaml.safe_load(profile_path.read_text(encoding="utf-8")) or {}
facts = data.get("facts") or []

GENERIC_TOKENS = {"fact", "qa", "ref", "value", "resource", "project", "domain", "owner"}

def tokenize(text: str) -> list[str]:
    return [token for token in re.split(r"[^a-z0-9]+", text.lower()) if token]

def semantic_key(fact: dict) -> tuple[str, str, str]:
    tokens = tokenize(str(fact.get("id", "")))
    semantic = "_".join(token for token in tokens if token not in GENERIC_TOKENS)
    value_ref = fact.get("value_ref")
    if isinstance(value_ref, dict):
        base_value = value_ref.get("answer") or value_ref.get("answer_redacted") or value_ref.get("secret_ref") or value_ref.get("question") or ""
    else:
        base_value = value_ref or ""
    value_sig = re.sub(r"\s+", " ", str(base_value).strip().lower())
    return (str(fact.get("type", "")), semantic, value_sig)

by_semantic: dict[tuple[str, str, str], list[dict]] = {}
for fact in facts:
    by_semantic.setdefault(semantic_key(fact), []).append(fact)

warnings = []

for key, grouped in by_semantic.items():
    project_scopes = [fact for fact in grouped if str(fact.get("scope", "")).startswith("project:")]
    if len(project_scopes) >= 2:
        distinct_scopes = sorted({fact.get("scope") for fact in project_scopes})
        if len(distinct_scopes) >= 2:
            warnings.append({
                "kind": "project_scope_duplication",
                "fact_ids": [fact.get("id") for fact in project_scopes],
                "scopes": distinct_scopes,
                "message": "project scope をまたぐ複製候補を検出",
            })

    none_transfer = [fact for fact in grouped if fact.get("transferability") == "none"]
    distinct_scopes = sorted({fact.get("scope") for fact in none_transfer})
    if len(distinct_scopes) >= 2:
        warnings.append({
            "kind": "transferability_none_violation",
            "fact_ids": [fact.get("id") for fact in none_transfer],
            "scopes": distinct_scopes,
            "message": "transferability:none の fact が複数 scope に存在",
        })

if warnings:
    print("[WARN] promote lint found transferability issues")
    for warning in warnings:
        print(f"- {warning['kind']}: {warning['message']}")
        print(f"  facts: {', '.join(warning['fact_ids'])}")
        print(f"  scopes: {', '.join(warning['scopes'])}")
else:
    print("[OK] promote lint found no transferability issues")
PY
