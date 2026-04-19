#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$ROOT_DIR/scripts/security/common.sh"

JSON_OUTPUT=0
if [[ "${1:-}" == "--json" ]]; then
  JSON_OUTPUT=1
fi

if ! require_python_yaml_or_skip; then
  if [[ "$JSON_OUTPUT" -eq 1 ]]; then
    printf '{"status":"skipped","warnings":[],"reason":"python3_or_pyyaml_missing"}\n'
  fi
  exit 0
fi

python3 - "$ROOT_DIR" "$JSON_OUTPUT" <<'PY'
from __future__ import annotations

import json
import pathlib
import re
import sys

import yaml

root = pathlib.Path(sys.argv[1])
json_output = sys.argv[2] == "1"
profile_path = root / ".ai" / "USER_PROFILE.yaml"

if not profile_path.exists():
    payload = {"status": "skipped", "warnings": [], "reason": "user_profile_missing"}
    if json_output:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        print("[WARN] .ai/USER_PROFILE.yaml が見つからないため normalize lint をスキップします", file=sys.stderr)
    sys.exit(0)

data = yaml.safe_load(profile_path.read_text(encoding="utf-8")) or {}
facts = data.get("facts") or []

GENERIC_TOKENS = {
    "fact", "qa", "value", "ref", "info", "data", "item", "entry",
    "resource", "project", "domain", "global", "owner",
}

def tokenize(text: str) -> list[str]:
    return [token for token in re.split(r"[^a-z0-9]+", text.lower()) if token]

def semantic_tokens(fact: dict) -> set[str]:
    tokens = []
    tokens.extend(tokenize(str(fact.get("id", ""))))
    tokens.extend(tokenize(str(fact.get("type", ""))))
    value_ref = fact.get("value_ref")
    if isinstance(value_ref, str):
        tokens.extend(tokenize(value_ref))
    elif isinstance(value_ref, dict):
        for key in ("question", "answer", "answer_redacted", "context", "secret_ref"):
            if value_ref.get(key):
                tokens.extend(tokenize(str(value_ref[key])))
    return {token for token in tokens if token not in GENERIC_TOKENS and len(token) >= 3}

def value_signature(fact: dict) -> str:
    value_ref = fact.get("value_ref")
    if isinstance(value_ref, dict):
        preferred = [
            value_ref.get("answer"),
            value_ref.get("answer_redacted"),
            value_ref.get("secret_ref"),
            value_ref.get("question"),
            value_ref.get("context"),
        ]
        raw = " ".join(str(item) for item in preferred if item)
    else:
        raw = str(value_ref or "")
    return re.sub(r"\s+", " ", raw.strip().lower())

def jaccard(tokens_a: set[str], tokens_b: set[str]) -> float:
    if not tokens_a or not tokens_b:
        return 0.0
    union = tokens_a | tokens_b
    if not union:
        return 0.0
    return len(tokens_a & tokens_b) / len(union)

warnings = []
seen_pairs = set()

for i, fact_a in enumerate(facts):
    for j in range(i + 1, len(facts)):
        fact_b = facts[j]
        pair_key = tuple(sorted((fact_a.get("id", f"idx:{i}"), fact_b.get("id", f"idx:{j}"))))
        if pair_key in seen_pairs:
            continue
        seen_pairs.add(pair_key)

        tokens_a = semantic_tokens(fact_a)
        tokens_b = semantic_tokens(fact_b)
        similarity = jaccard(tokens_a, tokens_b)
        shared = sorted(tokens_a & tokens_b)
        value_a = value_signature(fact_a)
        value_b = value_signature(fact_b)

        if similarity >= 0.5 and shared:
            warnings.append({
                "kind": "similar_id",
                "fact_ids": [fact_a.get("id"), fact_b.get("id")],
                "scope": [fact_a.get("scope"), fact_b.get("scope")],
                "type": [fact_a.get("type"), fact_b.get("type")],
                "shared_tokens": shared,
                "similarity": round(similarity, 2),
                "message": f"類似 semantic の fact id を検出: {fact_a.get('id')} / {fact_b.get('id')}",
            })
            continue

        same_scope_and_type = (
            fact_a.get("scope") == fact_b.get("scope")
            and fact_a.get("type") == fact_b.get("type")
        )
        value_overlap = value_a and value_b and (
            value_a == value_b
            or value_a in value_b
            or value_b in value_a
            or jaccard(set(tokenize(value_a)), set(tokenize(value_b))) >= 0.6
        )
        if same_scope_and_type and value_overlap:
            warnings.append({
                "kind": "duplicate_semantic",
                "fact_ids": [fact_a.get("id"), fact_b.get("id")],
                "scope": fact_a.get("scope"),
                "type": fact_a.get("type"),
                "value_refs": [value_a, value_b],
                "message": f"同一 scope/type かつ類似 value_ref の fact を検出: {fact_a.get('id')} / {fact_b.get('id')}",
            })

payload = {"status": "ok", "warnings": warnings}

if json_output:
    print(json.dumps(payload, ensure_ascii=False, indent=2))
else:
    if warnings:
        print("[WARN] normalize lint found potential duplicates")
        for warning in warnings:
            print(f"- {warning['kind']}: {warning['message']}")
    else:
        print("[OK] normalize lint found no duplicate semantics")
PY
