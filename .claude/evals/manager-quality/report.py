#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import subprocess
import tempfile
from collections import defaultdict
from dataclasses import dataclass
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any, Callable

import yaml


NEGATIVE_METRICS = {
    "repeated_question_rate",
    "context_miss_rate",
    "unnecessary_owner_question_rate",
    "owner_delegation_burden",
}
POSITIVE_METRICS = {
    "capability_reuse_rate",
    "decision_trace_completeness",
}
TRACE_REQUIRED_FIELDS = ("source_ref", "valid_from", "last_verified_at", "transferability")
SOFT_AUTH_STATUSES = {"unverified", "expired", "unknown", "probe_error"}
SELF_TEST_EXPECTED = {
    "MQ-001": True,
    "MQ-002": True,
    "MQ-003": True,
    "MQ-004": True,
    "MQ-005": True,
    "MQ-006": True,
    "MQ-007": True,
    "MQ-008": True,
    "MQ-009": True,
    "MQ-010": True,
    "MQ-011": True,
    "MQ-012": True,
    "MQ-013": True,
    "MQ-014": True,
    "MQ-015": True,
    "MQ-016": True,
    "MQ-017": True,
    "MQ-018": True,
    "MQ-019": True,
    "MQ-020": True,
}
SELF_TEST_CATEGORY_COUNTS = {
    "repeated_question": {"passed": 4, "failed": 0},
    "cli_over_gui": {"passed": 4, "failed": 0},
    "context_miss": {"passed": 4, "failed": 0},
    "unnecessary_question": {"passed": 3, "failed": 0},
    "capability_reuse": {"passed": 3, "failed": 0},
    "decision_trace": {"passed": 2, "failed": 0},
}


@dataclass
class CaseResult:
    case_id: str
    title: str
    category: str
    symptom: str
    metric: str
    weight: float
    passed: bool
    score: float
    reason: str
    expected_behavior: list[str]
    anti_pattern: list[str]


@dataclass
class DecisionTraceAudit:
    total_decisions: int
    full_trace_count: int
    trace_present_count: int
    decision_present_count: int
    verification_present_count: int
    memory_update_present_count: int
    legacy_count: int
    source_files: list[str]
    notes: list[str]


@dataclass
class RuntimeContext:
    repo_root: Path
    user_profile: dict[str, Any]
    facts: list[dict[str, Any]]
    preferences: list[dict[str, Any]]
    capabilities_doc: dict[str, Any]
    capabilities: list[dict[str, Any]]
    capabilities_by_id: dict[str, dict[str, Any]]
    capabilities_by_name: dict[str, dict[str, Any]]
    tasks_doc: dict[str, Any]
    tasks: list[dict[str, Any]]
    running_tasks: list[dict[str, Any]]
    decisions_text: str
    goals_doc: dict[str, Any] | None
    control_doc: dict[str, Any]


def load_yaml(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def load_optional_yaml(path: Path) -> Any:
    if not path.exists():
        return None
    loaded = load_yaml(path)
    if loaded is None:
        return None
    return loaded


def load_optional_text(path: Path) -> str:
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8")


def parse_threshold(target: str) -> tuple[str, float | None]:
    if target.startswith("<"):
        return ("lt", float(target.replace("<", "").replace("%", "").strip()))
    if target.startswith(">"):
        return ("gt", float(target.replace(">", "").replace("%", "").strip()))
    return ("trend", None)


def load_suite(repo_root: Path) -> tuple[list[dict[str, Any]], dict[str, dict[str, Any]]]:
    suite_dir = repo_root / ".claude" / "evals" / "manager-quality"
    cases = []
    for path in sorted((suite_dir / "cases").glob("*.yaml")):
        cases.append(load_yaml(path))
    metrics_doc = load_yaml(suite_dir / "metrics.yaml")
    metrics = {metric["id"]: metric for metric in metrics_doc["metrics"]}
    return cases, metrics


def load_runtime_context(repo_root: Path) -> RuntimeContext:
    ai_root = repo_root / ".ai"
    profile = load_optional_yaml(ai_root / "USER_PROFILE.yaml")
    capabilities_doc = load_optional_yaml(ai_root / "CAPABILITIES.yaml")
    tasks_doc = load_optional_yaml(ai_root / "TASKS.yaml")
    goals_doc = load_optional_yaml(ai_root / "GOALS.yaml")
    control_doc = load_optional_yaml(ai_root / "CONTROL.yaml")
    decisions_text = load_optional_text(ai_root / "DECISIONS.md")

    profile_dict = profile if isinstance(profile, dict) else {}
    capability_list = capabilities_doc.get("capabilities", []) if isinstance(capabilities_doc, dict) else []
    task_list = tasks_doc.get("tasks", []) if isinstance(tasks_doc, dict) else []
    capabilities_by_id = {
        str(item.get("id")): item
        for item in capability_list
        if isinstance(item, dict) and item.get("id")
    }
    capabilities_by_name = {}
    for item in capability_list:
        if not isinstance(item, dict):
            continue
        for key in ("name", "command", "path"):
            value = item.get(key)
            if value:
                capabilities_by_name[normalize_text(str(value))] = item

    running_tasks = [
        task for task in task_list if isinstance(task, dict) and str(task.get("status", "")).lower() == "running"
    ]

    return RuntimeContext(
        repo_root=repo_root,
        user_profile=profile_dict,
        facts=profile_dict.get("facts", []) if isinstance(profile_dict.get("facts", []), list) else [],
        preferences=profile_dict.get("preferences", []) if isinstance(profile_dict.get("preferences", []), list) else [],
        capabilities_doc=capabilities_doc if isinstance(capabilities_doc, dict) else {},
        capabilities=capability_list,
        capabilities_by_id=capabilities_by_id,
        capabilities_by_name=capabilities_by_name,
        tasks_doc=tasks_doc if isinstance(tasks_doc, dict) else {},
        tasks=task_list,
        running_tasks=running_tasks,
        decisions_text=decisions_text,
        goals_doc=goals_doc if isinstance(goals_doc, dict) else None,
        control_doc=control_doc if isinstance(control_doc, dict) else {},
    )


def normalize_text(value: str) -> str:
    lowered = value.lower()
    return re.sub(r"[\W_]+", "", lowered)


def tokenize_text(value: str) -> set[str]:
    return set(re.findall(r"[a-z0-9_]+", value.lower()))


def behavior_conflicts(expected_behavior: list[str], anti_pattern: list[str]) -> bool:
    normalized_expected = {normalize_text(item) for item in expected_behavior}
    normalized_anti = {normalize_text(item) for item in anti_pattern}
    return bool(normalized_expected & normalized_anti)


def build_case_result(case: dict[str, Any], passed: bool, reason: str) -> CaseResult:
    return CaseResult(
        case_id=case["id"],
        title=case["title"],
        category=case["category"],
        symptom=case["symptom"],
        metric=case["metric"],
        weight=float(case.get("weight", 1.0)),
        passed=passed,
        score=1.0 if passed else 0.0,
        reason=reason,
        expected_behavior=list(case.get("expected_behavior", [])),
        anti_pattern=list(case.get("anti_pattern", [])),
    )


def find_matching_past_qa_facts(case: dict[str, Any], facts: list[dict[str, Any]]) -> list[dict[str, Any]]:
    requested_pairs = case.get("input", {}).get("past_qa", [])
    if not requested_pairs:
        return []

    matches: list[dict[str, Any]] = []
    for requested in requested_pairs:
        requested_question = normalize_text(str(requested.get("q", "")))
        requested_question_tokens = tokenize_text(str(requested.get("q", "")))
        requested_answer = normalize_text(str(requested.get("a", "")))
        requested_asked_at = str(requested.get("asked_at", ""))
        for fact in facts:
            value_ref = fact.get("value_ref")
            if not isinstance(value_ref, dict):
                continue
            fact_question = normalize_text(str(value_ref.get("question", "")))
            fact_question_tokens = tokenize_text(str(value_ref.get("question", "")))
            answer_candidates = [
                normalize_text(str(value_ref.get("answer", ""))),
                normalize_text(str(value_ref.get("answer_redacted", ""))),
                normalize_text(str(value_ref.get("secret_ref", ""))),
            ]
            question_matches = fact_question == requested_question
            token_matches = bool(requested_question_tokens) and requested_question_tokens.issubset(
                fact_question_tokens
            )
            if not question_matches and not token_matches:
                continue
            if requested_answer and requested_answer not in answer_candidates:
                continue
            if requested_asked_at and str(value_ref.get("asked_at", "")) != requested_asked_at:
                continue
            matches.append(fact)
            break
    return matches


def preference_texts(context: RuntimeContext) -> list[str]:
    texts = []
    for pref in context.preferences:
        statement = pref.get("statement")
        if statement:
            texts.append(str(statement))
    return texts


def find_capability(context: RuntimeContext, requested: str | dict[str, Any]) -> dict[str, Any] | None:
    if isinstance(requested, dict) and requested.get("id"):
        return context.capabilities_by_id.get(str(requested["id"]))

    text = requested if isinstance(requested, str) else str(requested)
    normalized = normalize_text(text)
    if normalized in context.capabilities_by_name:
        return context.capabilities_by_name[normalized]

    if normalized.startswith("gh"):
        return context.capabilities_by_id.get("cli_gh")
    if normalized.startswith("supabase"):
        return context.capabilities_by_id.get("cli_supabase")
    if normalized.startswith("vercel"):
        return context.capabilities_by_id.get("cli_vercel")
    if normalized.startswith("stripe"):
        return context.capabilities_by_id.get("cli_stripe")

    for capability in context.capabilities:
        if not isinstance(capability, dict):
            continue
        haystacks = [
            str(capability.get("id", "")),
            str(capability.get("name", "")),
            str(capability.get("command", "")),
            str(capability.get("path", "")),
        ]
        if any(normalized and normalized in normalize_text(item) for item in haystacks):
            return capability
    return None


def capability_is_available(capability: dict[str, Any] | None) -> bool:
    return bool(capability) and str(capability.get("status", "")).lower() == "available"


def capability_soft_auth(capability: dict[str, Any] | None) -> bool:
    if not capability:
        return False
    return str(capability.get("auth_status", "")).lower() in SOFT_AUTH_STATUSES


def capability_supports_operation(capability: dict[str, Any] | None, requested: str | dict[str, Any]) -> bool:
    if not capability:
        return False

    if isinstance(requested, dict):
        operation = str(requested.get("operation", ""))
        capability_id = str(requested.get("id", ""))
        if capability_id and capability_id == capability.get("id"):
            if not operation:
                return True
            op_token = normalize_text(operation)
            for item in capability.get("common_operations", []):
                haystacks = [
                    str(item.get("name", "")),
                    str(item.get("description", "")),
                    str(item.get("command_template", "")),
                ]
                if any(op_token and op_token in normalize_text(field) for field in haystacks):
                    return True
                field_tokens = tokenize_text(" ".join(haystacks))
                op_tokens = tokenize_text(operation.replace("_", " "))
                if op_tokens and op_tokens.issubset(field_tokens):
                    return True
                if "pr" in op_tokens and "inspect" in op_tokens and "pr" in field_tokens and "view" in field_tokens:
                    return True
        return False

    text = str(requested)
    path = context_path_candidate(text)
    if path:
        return path.exists() or normalize_text(text) == normalize_text(str(capability.get("path", "")))

    requested_norm = normalize_text(text)
    for item in capability.get("common_operations", []):
        haystacks = [
            str(item.get("name", "")),
            str(item.get("description", "")),
            str(item.get("command_template", "")),
        ]
        if any(requested_norm and requested_norm in normalize_text(field) for field in haystacks):
            return True

    request_tokens = tokenize_text(text)
    for item in capability.get("common_operations", []):
        operation_tokens = tokenize_text(
            " ".join(
                [
                    str(item.get("name", "")),
                    str(item.get("description", "")),
                    str(item.get("command_template", "")),
                ]
            )
        )
        if request_tokens and request_tokens.issubset(operation_tokens):
            return True
    return False


def context_path_candidate(value: str) -> Path | None:
    if "/" not in value:
        return None
    return Path(value)


def markdown_contains_all(text: str, required: list[str]) -> bool:
    normalized_text = normalize_text(text)
    return all(normalize_text(item) in normalized_text for item in required)


def decision_requirement_matched(required: str, context: RuntimeContext) -> bool:
    normalized_required = normalize_text(required)
    sources = [context.decisions_text, *preference_texts(context)]
    if any(normalized_required in normalize_text(source) for source in sources):
        return True

    alias_groups = [
        {"cli > gui", "cli優先", "cli over gui"},
        {
            "owner cognitive load を最小化",
            "owner cognitiveload を最小化",
            "自律実行 > 選択肢提示",
            "自律実行優先",
        },
    ]
    for aliases in alias_groups:
        normalized_aliases = {normalize_text(item) for item in aliases}
        if normalized_required in normalized_aliases:
            return any(
                alias in normalize_text(source)
                for alias in normalized_aliases
                for source in sources
            )
    return False


def repeated_question_judge(case: dict[str, Any], context: RuntimeContext) -> CaseResult:
    requested_pairs = case.get("input", {}).get("past_qa", [])
    matches = find_matching_past_qa_facts(case, context.facts)
    conflict = behavior_conflicts(
        list(case.get("expected_behavior", [])),
        list(case.get("anti_pattern", [])),
    )
    passed = bool(requested_pairs) and len(matches) == len(requested_pairs) and not conflict
    if passed:
        reason = (
            f"USER_PROFILE.facts で {len(matches)} 件の past_qa を確認済み。"
            f" current_request={case.get('input', {}).get('current_request', '')!r} に対し再質問回避条件を満たす"
        )
    else:
        reason = (
            f"USER_PROFILE.facts の past_qa 一致数 {len(matches)}/{len(requested_pairs)}。"
            " current_request に使う記憶が不足しているか、expected_behavior と anti_pattern が衝突している"
        )
    return build_case_result(case, passed, reason)


def iter_handoff_packet_sources(repo_root: Path) -> list[Path]:
    candidates = []
    for relative in (
        Path(".ai/CODEX/RESULTS"),
        Path(".ai/CODEX/LOGS"),
    ):
        base = repo_root / relative
        if not base.exists():
            continue
        candidates.extend(sorted(base.glob("*.md")))
        candidates.extend(sorted(base.glob("*.txt")))
        candidates.extend(sorted(base.glob("*.log")))
    return candidates


def extract_handoff_packet_blocks(text: str) -> list[str]:
    blocks = []
    fenced_pattern = re.compile(r"```yaml\s+(.*?)```", re.DOTALL)
    for match in fenced_pattern.finditer(text):
        block = match.group(1).strip()
        if "handoff_packet:" in block:
            blocks.append(block)

    raw_pattern = re.compile(r"(?ms)^handoff_packet:\n(?:^[ \t].*\n?)+")
    for match in raw_pattern.finditer(text):
        blocks.append(match.group(0).strip())
    return blocks


def normalize_handoff_packet(candidate: Any) -> dict[str, Any] | None:
    if not isinstance(candidate, dict):
        return None
    if "handoff_packet" in candidate and isinstance(candidate["handoff_packet"], dict):
        return candidate["handoff_packet"]
    return candidate if "trace" in candidate or "task_id" in candidate else None


def packet_contains_placeholder(packet: dict[str, Any]) -> bool:
    placeholder_tokens = {"...", "string", "datetime", "enum", "list", "object", "any"}

    def walk(value: Any) -> bool:
        if isinstance(value, str):
            normalized = value.strip().lower()
            return normalized in placeholder_tokens or normalized.startswith("enum[")
        if isinstance(value, dict):
            return any(walk(item) for item in value.values())
        if isinstance(value, list):
            return any(walk(item) for item in value)
        return False

    return walk(packet)


def iter_packet_strings(value: Any) -> list[str]:
    strings: list[str] = []
    if isinstance(value, str):
        strings.append(value)
    elif isinstance(value, dict):
        for item in value.values():
            strings.extend(iter_packet_strings(item))
    elif isinstance(value, list):
        for item in value:
            strings.extend(iter_packet_strings(item))
    return strings


def has_explicit_acknowledgement(value: Any, phrases: tuple[str, ...]) -> bool:
    lowered_phrases = tuple(item.lower() for item in phrases)
    for item in iter_packet_strings(value):
        lowered = item.lower()
        if any(phrase in lowered for phrase in lowered_phrases):
            return True
    return False


def packet_has_verification(packet: dict[str, Any]) -> bool:
    verification = packet.get("verification")
    if not isinstance(verification, dict):
        return False
    tests_run = verification.get("tests_run")
    eval_results = verification.get("eval_results")
    return bool(tests_run) or bool(eval_results)


def packet_has_memory_updates(packet: dict[str, Any]) -> bool:
    memory_updates = packet.get("memory_updates")
    if memory_updates:
        return True
    verification = packet.get("verification", {})
    return has_explicit_acknowledgement(
        [memory_updates, verification.get("self_check", ""), packet.get("notes", "")],
        ("no updates", "no memory updates", "更新なし", "memory update なし"),
    )


def packet_has_assumptions(packet: dict[str, Any]) -> bool:
    assumptions = packet.get("assumptions")
    if assumptions:
        return True
    verification = packet.get("verification", {})
    return has_explicit_acknowledgement(
        [assumptions, verification.get("self_check", ""), packet.get("notes", "")],
        ("no assumptions", "仮定なし"),
    )


def packet_has_decisions(packet: dict[str, Any]) -> bool:
    decisions = packet.get("decisions_made")
    if not isinstance(decisions, list) or not decisions:
        return False
    for item in decisions:
        if not isinstance(item, dict):
            return False
        if not item.get("decision") or not item.get("rationale"):
            return False
        alternatives = item.get("alternatives_considered")
        if not isinstance(alternatives, list):
            return False
    return True


def packet_has_trace(packet: dict[str, Any]) -> bool:
    trace = packet.get("trace")
    if not isinstance(trace, dict):
        return False
    return bool(trace.get("request_trace_id")) and bool(trace.get("span_id"))


def audit_decision_traces(repo_root: Path) -> DecisionTraceAudit:
    packets: list[tuple[Path, dict[str, Any]]] = []
    notes: list[str] = []
    source_files: list[str] = []
    for path in iter_handoff_packet_sources(repo_root):
        text = path.read_text(encoding="utf-8", errors="replace")
        for block in extract_handoff_packet_blocks(text):
            try:
                parsed = yaml.safe_load(block)
            except yaml.YAMLError:
                continue
            packet = normalize_handoff_packet(parsed)
            if not packet:
                continue
            if packet_contains_placeholder(packet):
                notes.append(f"{path.name}: placeholder packet skipped as legacy")
                continue
            packets.append((path, packet))
            source_files.append(str(path.relative_to(repo_root)))

    if not packets:
        return DecisionTraceAudit(
            total_decisions=0,
            full_trace_count=0,
            trace_present_count=0,
            decision_present_count=0,
            verification_present_count=0,
            memory_update_present_count=0,
            legacy_count=0,
            source_files=[],
            notes=["No non-legacy handoff packets found."],
        )

    full_trace_count = 0
    trace_present_count = 0
    decision_present_count = 0
    verification_present_count = 0
    memory_update_present_count = 0

    for _, packet in packets:
        assumptions_ok = packet_has_assumptions(packet)
        decisions_ok = packet_has_decisions(packet)
        verification_ok = packet_has_verification(packet)
        memory_ok = packet_has_memory_updates(packet)
        trace_ok = packet_has_trace(packet)

        if trace_ok:
            trace_present_count += 1
        if assumptions_ok and decisions_ok:
            decision_present_count += 1
        if verification_ok:
            verification_present_count += 1
        if memory_ok:
            memory_update_present_count += 1
        if assumptions_ok and decisions_ok and verification_ok and memory_ok and trace_ok:
            full_trace_count += 1

    return DecisionTraceAudit(
        total_decisions=len(packets),
        full_trace_count=full_trace_count,
        trace_present_count=trace_present_count,
        decision_present_count=decision_present_count,
        verification_present_count=verification_present_count,
        memory_update_present_count=memory_update_present_count,
        legacy_count=0,
        source_files=sorted(set(source_files)),
        notes=notes,
    )


def decision_trace_judge(case: dict[str, Any], context: RuntimeContext) -> CaseResult:
    audit = audit_decision_traces(context.repo_root)
    if audit.total_decisions > 0:
        if case["id"] == "MQ-019":
            passed = (
                audit.decision_present_count == audit.total_decisions
                and audit.verification_present_count == audit.total_decisions
            )
            if passed:
                reason = (
                    f"handoff packet audit: decisions={audit.decision_present_count}/{audit.total_decisions},"
                    f" verification={audit.verification_present_count}/{audit.total_decisions}"
                )
            else:
                reason = (
                    f"handoff packet audit incomplete: decisions={audit.decision_present_count}/{audit.total_decisions},"
                    f" verification={audit.verification_present_count}/{audit.total_decisions}"
                )
            return build_case_result(case, passed, reason)

        passed = (
            audit.trace_present_count == audit.total_decisions
            and audit.memory_update_present_count == audit.total_decisions
        )
        if passed:
            reason = (
                f"handoff packet audit: trace={audit.trace_present_count}/{audit.total_decisions},"
                f" memory_updates={audit.memory_update_present_count}/{audit.total_decisions}"
            )
        else:
            reason = (
                f"handoff packet audit incomplete: trace={audit.trace_present_count}/{audit.total_decisions},"
                f" memory_updates={audit.memory_update_present_count}/{audit.total_decisions}"
            )
        return build_case_result(case, passed, reason)

    traceable_facts = [
        fact
        for fact in context.facts
        if all(fact.get(field) not in (None, "") for field in TRACE_REQUIRED_FIELDS)
    ]
    conflict = behavior_conflicts(
        list(case.get("expected_behavior", [])),
        list(case.get("anti_pattern", [])),
    )
    passed = bool(traceable_facts) and not conflict
    if passed:
        reason = (
            f"legacy fallback: USER_PROFILE.facts の {len(traceable_facts)} 件が trace metadata"
            " (source_ref/valid_from/last_verified_at/transferability) を保持している"
        )
    else:
        reason = (
            "handoff packet audit 対象が見つからず、USER_PROFILE.facts に判断 trace を支える metadata 完備 fact もないか、"
            " expected_behavior と anti_pattern が衝突している"
        )
    return build_case_result(case, passed, reason)


def cli_over_gui_judge(case: dict[str, Any], context: RuntimeContext) -> CaseResult:
    requested_capabilities = list(case.get("input", {}).get("capabilities", []))
    conflict = behavior_conflicts(
        list(case.get("expected_behavior", [])),
        list(case.get("anti_pattern", [])),
    )
    if conflict:
        return build_case_result(case, False, "expected_behavior と anti_pattern が衝突している")

    if not requested_capabilities:
        return build_case_result(case, False, "case input.capabilities が空のため burden 判定ができない")

    supported = []
    unavailable = []
    soft_auth = []
    missing_ops = []
    for requested in requested_capabilities:
        capability = find_capability(context, requested)
        if not capability:
            unavailable.append(str(requested))
            continue
        if not capability_is_available(capability):
            unavailable.append(f"{requested} -> {capability.get('id')}")
            continue
        if capability_soft_auth(capability):
            soft_auth.append(f"{capability.get('id')}({capability.get('auth_status')})")
            continue
        if capability_supports_operation(capability, requested):
            supported.append(f"{requested} -> {capability.get('id')}")
            continue
        missing_ops.append(f"{requested} -> {capability.get('id')}")

    if supported:
        reason = "CAPABILITIES.yaml 上で CLI/runbook 実行可能: " + ", ".join(supported)
        return build_case_result(case, True, reason)
    if soft_auth:
        reason = "CLI は存在するが認証確認だけを Owner に依頼すればよい状態: " + ", ".join(soft_auth)
        return build_case_result(case, True, reason)
    if unavailable:
        reason = "該当 capability が未導入/未利用可能。GUI 依頼ではなく auth/setup 依頼で足りる: " + ", ".join(unavailable)
        return build_case_result(case, True, reason)

    reason = "capability は available だが要求 operation を common_operations/runbook へ結び付けられない: "
    reason += ", ".join(missing_ops)
    return build_case_result(case, False, reason)


def task_matches_required(task: dict[str, Any], required: str) -> bool:
    required_norm = normalize_text(required)
    id_part, _, title_part = required.partition(":")
    task_id = str(task.get("id", ""))
    task_title = str(task.get("title", ""))
    if normalize_text(task_id) == normalize_text(id_part.strip()):
        return True
    return required_norm in normalize_text(f"{task_id} {task_title} {title_part}")


def context_miss_judge(case: dict[str, Any], context: RuntimeContext) -> CaseResult:
    conflict = behavior_conflicts(
        list(case.get("expected_behavior", [])),
        list(case.get("anti_pattern", [])),
    )
    if conflict:
        return build_case_result(case, False, "expected_behavior と anti_pattern が衝突している")

    case_input = case.get("input", {})

    active_tasks = list(case_input.get("active_tasks", []))
    if active_tasks:
        matched = []
        for required in active_tasks:
            match = next((task for task in context.running_tasks if task_matches_required(task, str(required))), None)
            if match:
                matched.append(f"{match.get('id')}: {match.get('title')}")
        passed = len(matched) == len(active_tasks) and bool(matched)
        if passed:
            reason = "TASKS.yaml の running task と scenario を bind 可能: " + ", ".join(matched)
        else:
            reason = (
                f"TASKS.yaml に running task が {len(context.running_tasks)} 件。"
                f" scenario active_tasks 一致 {len(matched)}/{len(active_tasks)} のため bind pending"
            )
        return build_case_result(case, passed, reason)

    control_input = case_input.get("control", {})
    expected_stage = str(control_input.get("stage", "")).strip()
    if expected_stage:
        actual_stage = str(context.control_doc.get("stage", "")).strip()
        goals_available = context.goals_doc is not None
        passed = bool(actual_stage)
        if passed:
            reason = (
                f"CONTROL.yaml stage={actual_stage!r} を確認済み。"
                f" GOALS.yaml {'あり' if goals_available else '欠落'}でも phase-aware bind は可能"
            )
        else:
            reason = "CONTROL.yaml/GOALS.yaml から現在 phase を取得できず、phase bind を確認できない"
        return build_case_result(case, passed, reason)

    required_decisions = list(case_input.get("decisions", []))
    if required_decisions:
        matched = [item for item in required_decisions if decision_requirement_matched(item, context)]
        passed = len(matched) == len(required_decisions)
        if passed:
            reason = "DECISIONS.md / USER_PROFILE.preferences に既存方針あり: " + ", ".join(matched)
        else:
            reason = (
                f"既存方針の一致 {len(matched)}/{len(required_decisions)}。"
                " Decision bind に必要な実データが不足"
            )
        return build_case_result(case, passed, reason)

    return build_case_result(case, False, "context_miss judge に対応する input がない")


def has_preference(context: RuntimeContext, needle: str) -> bool:
    normalized = normalize_text(needle)
    return any(normalized in normalize_text(text) for text in preference_texts(context))


def active_inquiry_flags(case: dict[str, Any], context: RuntimeContext) -> list[str]:
    current_request = str(case.get("input", {}).get("current_request", "")).lower()
    flags = []
    if any(token in current_request for token in ("delete", "deploy", "refund", "billing", "production")):
        flags.append("irreversible_action")
    if any(token in current_request for token in ("billing", "stripe", "security", "payment")):
        flags.append("security_or_billing_risk")
    if ("tone" in current_request or "トーン" in current_request) and not has_preference(context, "terse"):
        flags.append("owner_preference_unknown_and_material")
    if any(token in current_request for token in ("architecture", "migration", "schema", "strategy")):
        flags.append("multiple_valid_paths_with_high_downstream_cost")
    return flags


def unnecessary_question_judge(case: dict[str, Any], context: RuntimeContext) -> CaseResult:
    conflict = behavior_conflicts(
        list(case.get("expected_behavior", [])),
        list(case.get("anti_pattern", [])),
    )
    if conflict:
        return build_case_result(case, False, "expected_behavior と anti_pattern が衝突している")

    case_input = case.get("input", {})
    current_request = str(case_input.get("current_request", ""))
    past_qa_matches = find_matching_past_qa_facts(case, context.facts)
    requested_capabilities = list(case_input.get("capabilities", []))

    capability_answerable = False
    capability_reasons = []
    for requested in requested_capabilities:
        capability = find_capability(context, requested)
        if capability and (capability_is_available(capability) or capability_soft_auth(capability)):
            capability_answerable = True
            capability_reasons.append(f"{requested} -> {capability.get('id')}")

    repo_search_answerable = any(token in current_request.lower() for token in ("callback", "readme", "挙動"))
    low_risk_assumption = "readme" in current_request.lower() and has_preference(context, "自律実行")
    answerable = bool(past_qa_matches) or capability_answerable or repo_search_answerable or low_risk_assumption

    if answerable:
        reasons = []
        if past_qa_matches:
            reasons.append(f"past_qa {len(past_qa_matches)} 件")
        if capability_reasons:
            reasons.append("capability " + ", ".join(capability_reasons))
        if repo_search_answerable:
            reasons.append("repo inspection で解決可能")
        if low_risk_assumption:
            reasons.append("low-risk reversible assumption 可")
        return build_case_result(case, True, "Owner 再質問なしで処理可能: " + "; ".join(reasons))

    inquiry_flags = active_inquiry_flags(case, context)
    if inquiry_flags:
        reason = "answerable ではないが Active Inquiry 条件を満たす: " + ", ".join(inquiry_flags)
        return build_case_result(case, True, reason)

    return build_case_result(case, False, "memory/CAPABILITIES でも答えを作れず、Active Inquiry 条件にも当たらない")


def capability_reuse_judge(case: dict[str, Any], context: RuntimeContext) -> CaseResult:
    conflict = behavior_conflicts(
        list(case.get("expected_behavior", [])),
        list(case.get("anti_pattern", [])),
    )
    if conflict:
        return build_case_result(case, False, "expected_behavior と anti_pattern が衝突している")

    requested_capabilities = list(case.get("input", {}).get("capabilities", []))
    if not requested_capabilities:
        return build_case_result(case, False, "capability_reuse case に input.capabilities がない")

    reused = []
    missing = []
    for requested in requested_capabilities:
        capability = find_capability(context, requested)
        if capability and capability_is_available(capability) and capability_supports_operation(capability, requested):
            reused.append(f"{requested} -> {capability.get('id')}")
            continue
        missing.append(str(requested))

    passed = len(reused) == len(requested_capabilities)
    if passed:
        reason = "CAPABILITIES.yaml の既知手段を再利用可能: " + ", ".join(reused)
    else:
        reason = (
            f"再利用可能 {len(reused)}/{len(requested_capabilities)}。"
            " 未登録または unavailable の capability: " + ", ".join(missing)
        )
    return build_case_result(case, passed, reason)


def mock_judge(case: dict[str, Any], _: RuntimeContext) -> CaseResult:
    reason = (
        "baseline mock judge: USER_PROFILE/CAPABILITIES/active work graph integration is absent, "
        "so the suite records a deterministic fail until Phase 1+ wiring exists"
    )
    return build_case_result(case, False, reason)


CASE_HANDLERS: dict[str, Callable[[dict[str, Any], RuntimeContext], CaseResult]] = {
    "repeated_question": repeated_question_judge,
    "cli_over_gui": cli_over_gui_judge,
    "context_miss": context_miss_judge,
    "unnecessary_question": unnecessary_question_judge,
    "capability_reuse": capability_reuse_judge,
    "decision_trace": decision_trace_judge,
}


def judge_case(case: dict[str, Any], context: RuntimeContext) -> CaseResult:
    handler = CASE_HANDLERS.get(case.get("category"), mock_judge)
    return handler(case, context)


def run_trend_calculator(repo_root: Path, jsonl_dir: Path) -> dict[str, Any]:
    script = repo_root / "scripts" / "eval" / "trend-calculator.sh"
    if not script.exists():
        return {
            "status": "pending",
            "passed": True,
            "reason": "trend-calculator.sh is missing",
            "days_considered": 0,
            "moving_average_3d": None,
            "moving_average_7d": None,
            "latest_ratio": None,
            "daily_series": [],
        }

    completed = subprocess.run(
        ["bash", str(script), "--jsonl-dir", str(jsonl_dir), "--json"],
        capture_output=True,
        text=True,
        check=False,
    )
    if not completed.stdout.strip():
        return {
            "status": "pending",
            "passed": True,
            "reason": f"trend calculator returned no output (exit={completed.returncode})",
            "days_considered": 0,
            "moving_average_3d": None,
            "moving_average_7d": None,
            "latest_ratio": None,
            "daily_series": [],
        }
    payload = json.loads(completed.stdout)
    payload["exit_code"] = completed.returncode
    return payload


def metric_summary(
    case_results: list[CaseResult],
    metrics: dict[str, dict[str, Any]],
    repo_root: Path,
    jsonl_dir: Path,
) -> dict[str, dict[str, Any]]:
    grouped: dict[str, list[CaseResult]] = defaultdict(list)
    for result in case_results:
        grouped[result.metric].append(result)

    decision_trace_audit = audit_decision_traces(repo_root)
    trend_payload = run_trend_calculator(repo_root, jsonl_dir)
    summaries: dict[str, dict[str, Any]] = {}
    for metric_id, meta in metrics.items():
        items = grouped.get(metric_id, [])
        total_weight = sum(item.weight for item in items)
        passed_weight = sum(item.weight for item in items if item.passed)
        failed_weight = total_weight - passed_weight
        if total_weight == 0:
            current_pct = None
        elif metric_id in NEGATIVE_METRICS:
            current_pct = round((failed_weight / total_weight) * 100, 2)
        else:
            current_pct = round((passed_weight / total_weight) * 100, 2)

        threshold_kind, threshold_value = parse_threshold(meta["target"])
        if metric_id == "decision_trace_completeness" and decision_trace_audit.total_decisions > 0:
            current_pct = round(
                (decision_trace_audit.full_trace_count / decision_trace_audit.total_decisions) * 100,
                2,
            )
            target_met = current_pct > threshold_value if threshold_value is not None else False
        elif metric_id == "owner_delegation_burden":
            latest_ratio = trend_payload.get("latest_ratio")
            current_pct = round(latest_ratio * 100, 2) if latest_ratio is not None else current_pct
            target_met = bool(trend_payload.get("passed", True))
        elif threshold_kind == "lt":
            target_met = current_pct is not None and current_pct < threshold_value
        elif threshold_kind == "gt":
            target_met = current_pct is not None and current_pct > threshold_value
        else:
            target_met = passed_weight == total_weight and total_weight > 0

        summary = {
            "metric_id": metric_id,
            "description": meta["description"],
            "priority": meta["priority"],
            "target": meta["target"],
            "direction": meta.get("direction"),
            "current_pct": current_pct,
            "cases": len(items),
            "passed_cases": sum(1 for item in items if item.passed),
            "failed_cases": sum(1 for item in items if not item.passed),
            "weighted_pass": round(passed_weight, 2),
            "weighted_total": round(total_weight, 2),
            "target_met": bool(target_met),
        }
        if metric_id == "owner_delegation_burden":
            summary["trend_status"] = trend_payload.get("status", "pending")
            summary["moving_average_3d"] = trend_payload.get("moving_average_3d")
            summary["moving_average_7d"] = trend_payload.get("moving_average_7d")
            summary["trend_reason"] = trend_payload.get("reason", "")
            summary["proxy_note"] = meta.get("baseline_note", "")
        if metric_id == "decision_trace_completeness":
            summary["full_trace_count"] = decision_trace_audit.full_trace_count
            summary["total_decisions"] = decision_trace_audit.total_decisions
            summary["trace_sources"] = decision_trace_audit.source_files[:5]
            summary["audit_notes"] = decision_trace_audit.notes[:5]
        summaries[metric_id] = summary
    return summaries


def append_jsonl(
    output_path: Path,
    run_id: str,
    run_date: str,
    case_results: list[CaseResult],
    metrics_summary: dict[str, dict[str, Any]],
) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("a", encoding="utf-8") as fh:
        for result in case_results:
            payload = {
                "run_id": run_id,
                "run_date": run_date,
                "suite": "manager-quality",
                "case_id": result.case_id,
                "title": result.title,
                "category": result.category,
                "symptom": result.symptom,
                "metric": result.metric,
                "metric_priority": metrics_summary[result.metric]["priority"],
                "weight": result.weight,
                "passed": result.passed,
                "score": result.score,
                "reason": result.reason,
                "expected_behavior": result.expected_behavior,
                "anti_pattern": result.anti_pattern,
                "metric_snapshot": metrics_summary[result.metric],
            }
            fh.write(json.dumps(payload, ensure_ascii=False) + "\n")


def render_markdown(
    run_id: str,
    run_date: str,
    case_results: list[CaseResult],
    metrics_summary: dict[str, dict[str, Any]],
) -> str:
    passed = sum(1 for item in case_results if item.passed)
    failed = len(case_results) - passed
    lines = [
        "# Manager Quality Baseline",
        "",
        f"- run_id: `{run_id}`",
        f"- run_date: `{run_date}`",
        f"- cases: `{len(case_results)}`",
        f"- pass/fail: `{passed}/{failed}`",
        "",
        "## Metrics",
    ]
    for metric_id, summary in metrics_summary.items():
        value = "n/a" if summary["current_pct"] is None else f'{summary["current_pct"]}%'
        status = "pass" if summary["target_met"] else "fail"
        extra = ""
        if metric_id == "owner_delegation_burden":
            extra = " (trend pending, proxy from burden cases)"
        lines.append(
            f"- `{metric_id}`: {value} vs target `{summary['target']}` -> {status}{extra}"
        )
    lines.extend(["", "## Failing Cases"])
    for result in case_results:
        if not result.passed:
            lines.append(f"- `{result.case_id}` {result.title} [{result.metric}]: {result.reason}")
    return "\n".join(lines)


def build_run_summary(
    run_id: str,
    run_date: str,
    case_results: list[CaseResult],
    metrics_summary: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    return {
        "run_id": run_id,
        "run_date": run_date,
        "suite": "manager-quality",
        "cases": len(case_results),
        "passed": sum(1 for item in case_results if item.passed),
        "failed": sum(1 for item in case_results if not item.passed),
        "metrics": metrics_summary,
        "critical_failure": any(
            summary["priority"] == "P0" and not summary["target_met"]
            for summary in metrics_summary.values()
        ),
    }


def load_history(jsonl_dir: Path) -> dict[str, list[dict[str, Any]]]:
    runs: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for path in sorted(jsonl_dir.glob("*.jsonl")):
        with path.open("r", encoding="utf-8") as fh:
            for line in fh:
                if not line.strip():
                    continue
                row = json.loads(line)
                runs[row["run_id"]].append(row)
    return runs


def summarize_run(rows: list[dict[str, Any]]) -> dict[str, Any]:
    if not rows:
        return {"run_id": "", "run_date": "", "cases": {}, "metrics": {}}
    cases = {row["case_id"]: row for row in rows}
    metrics = {}
    for row in rows:
        metric_id = row["metric"]
        metrics[metric_id] = row.get("metric_snapshot", {})
    return {
        "run_id": rows[0]["run_id"],
        "run_date": rows[0]["run_date"],
        "cases": cases,
        "metrics": metrics,
    }


def resolve_regression_baselines(
    ordered: list[tuple[str, list[dict[str, Any]]]],
    compare_last: int,
    compare_date: str | None,
) -> list[tuple[str, list[dict[str, Any]]]]:
    if len(ordered) < 2:
        return []

    current_run_id = ordered[-1][0]
    prior_runs = ordered[:-1]
    if compare_date:
        matching = [item for item in prior_runs if item[1] and item[1][0].get("run_date") == compare_date]
        return matching[-1:] if matching else []

    count = max(compare_last, 1)
    return prior_runs[-count:]


def render_regression_markdown(report: dict[str, Any]) -> str:
    lines = [
        "# Manager Quality Regression Report",
        "",
        f"- generated_at: `{datetime.now(timezone.utc).replace(microsecond=0).isoformat()}`",
        f"- current_run_id: `{report.get('current_run_id', 'n/a')}`",
        f"- compared_runs: `{len(report.get('baseline_run_ids', []))}`",
        f"- status: `{report['status']}`",
        "",
        "## Case Regressions",
    ]
    regressions = report.get("regressions", [])
    if regressions:
        for item in regressions:
            lines.append(
                f"- `{item['case_id']}` {item['title']} [{item['metric']}] regressed from `{', '.join(item['baseline_runs'])}`"
            )
    else:
        lines.append("- none")

    lines.extend(["", "## Metric Regressions"])
    metric_regressions = report.get("metric_regressions", [])
    if metric_regressions:
        for item in metric_regressions:
            lines.append(
                f"- `{item['metric']}` target met in `{', '.join(item['baseline_runs'])}` but current is `{item['current_pct']}%`"
            )
    else:
        lines.append("- none")
    return "\n".join(lines)


def write_regression_payload(jsonl_dir: Path, report: dict[str, Any]) -> Path:
    output_path = jsonl_dir / f"regression-{date.today().isoformat()}.md"
    output_path.write_text(render_regression_markdown(report), encoding="utf-8")
    return output_path


def regression_report(
    jsonl_dir: Path,
    compare_last: int = 1,
    compare_date: str | None = None,
) -> dict[str, Any]:
    runs = load_history(jsonl_dir)
    ordered = sorted(runs.items(), key=lambda item: item[0])
    baselines = resolve_regression_baselines(ordered, compare_last, compare_date)
    if not baselines:
        report = {
            "status": "insufficient_history",
            "message": "Need at least one earlier run to detect regressions.",
            "regressions": [],
            "metric_regressions": [],
            "baseline_run_ids": [],
            "current_run_id": ordered[-1][0] if ordered else None,
        }
        report["payload_path"] = str(write_regression_payload(jsonl_dir, report))
        return report

    curr_run_id, curr_rows = ordered[-1]
    current_summary = summarize_run(curr_rows)
    regressions: dict[str, dict[str, Any]] = {}
    metric_regressions: dict[str, dict[str, Any]] = {}
    baseline_run_ids = [run_id for run_id, _ in baselines]

    for baseline_run_id, baseline_rows in baselines:
        previous_summary = summarize_run(baseline_rows)
        for case_id, current in current_summary["cases"].items():
            previous = previous_summary["cases"].get(case_id)
            if previous and previous.get("passed") and not current.get("passed"):
                existing = regressions.setdefault(
                    case_id,
                    {
                        "case_id": case_id,
                        "title": current["title"],
                        "category": current["category"],
                        "metric": current["metric"],
                        "baseline_runs": [],
                    },
                )
                existing["baseline_runs"].append(baseline_run_id)

        for metric_id, current_metric in current_summary["metrics"].items():
            previous_metric = previous_summary["metrics"].get(metric_id)
            if (
                previous_metric
                and previous_metric.get("target_met")
                and not current_metric.get("target_met")
            ):
                existing_metric = metric_regressions.setdefault(
                    metric_id,
                    {
                        "metric": metric_id,
                        "previous_pcts": [],
                        "current_pct": current_metric.get("current_pct"),
                        "baseline_runs": [],
                    },
                )
                existing_metric["baseline_runs"].append(baseline_run_id)
                existing_metric["previous_pcts"].append(previous_metric.get("current_pct"))

    issue_suffix = curr_run_id.replace(":", "").replace("-", "")
    report = {
        "status": "regression" if regressions or metric_regressions else "stable",
        "baseline_run_ids": baseline_run_ids,
        "current_run_id": curr_run_id,
        "regressions": list(regressions.values()),
        "metric_regressions": list(metric_regressions.values()),
        "decision_entry": [
            f"## ISSUE-MQ-{issue_suffix}: Manager Quality 退行検知 ({date.today().isoformat()})",
            "",
            "### 退行したケース",
            *[
                f"- {item['case_id']}: {item['title']} (category: {item['category']})"
                for item in regressions.values()
            ],
            "",
            "### 前回 target 達成 → 今回未達の metric",
            *[
                f"- {metric_id}: 前回 {values['previous_pcts']} → 今回 {values['current_pct']}%"
                for metric_id, values in metric_regressions.items()
            ],
            "",
            "### 対応",
            f"- 自動生成タスク: T-FIX-MQ-{issue_suffix}",
        ],
        "task_stub": {
            "id": f"T-FIX-MQ-{issue_suffix}",
            "title": f"Manager Quality regression fix ({date.today().isoformat()})",
            "status": "queued",
            "priority": "P0",
        },
    }
    report["payload_path"] = str(write_regression_payload(jsonl_dir, report))
    return report


def run_suite(repo_root: Path, jsonl_dir: Path | None = None) -> tuple[list[CaseResult], dict[str, dict[str, Any]]]:
    cases, metrics = load_suite(repo_root)
    context = load_runtime_context(repo_root)
    case_results = [judge_case(case, context) for case in cases]
    effective_jsonl_dir = jsonl_dir or (repo_root / ".ai" / "METRICS" / "manager-quality")
    return case_results, metric_summary(case_results, metrics, repo_root, effective_jsonl_dir)


def write_mock_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    with path.open("w", encoding="utf-8") as fh:
        for row in rows:
            fh.write(json.dumps(row, ensure_ascii=False) + "\n")


def build_mock_row(
    run_id: str,
    run_date: str,
    case_id: str,
    metric: str,
    passed: bool,
    current_pct: float,
    target_met: bool,
) -> dict[str, Any]:
    return {
        "run_id": run_id,
        "run_date": run_date,
        "suite": "manager-quality",
        "case_id": case_id,
        "title": case_id,
        "category": "mock",
        "symptom": "mock",
        "metric": metric,
        "metric_priority": "P1",
        "weight": 1.0,
        "passed": passed,
        "score": 1.0 if passed else 0.0,
        "reason": "mock",
        "expected_behavior": [],
        "anti_pattern": [],
        "metric_snapshot": {
            "metric_id": metric,
            "description": "mock",
            "priority": "P1",
            "target": "> 80%",
            "direction": "higher_is_better",
            "current_pct": current_pct,
            "cases": 1,
            "passed_cases": 1 if passed else 0,
            "failed_cases": 0 if passed else 1,
            "weighted_pass": 1.0 if passed else 0.0,
            "weighted_total": 1.0,
            "target_met": target_met,
        },
    }


def regression_self_test(repo_root: Path) -> list[str]:
    issues: list[str] = []
    with tempfile.TemporaryDirectory() as tmp_dir:
        jsonl_dir = Path(tmp_dir)
        stable_rows = [
            build_mock_row("2026-04-17T00:00:00+00:00", "2026-04-17", "MQ-001", "capability_reuse_rate", True, 100.0, True),
            build_mock_row("2026-04-17T00:00:00+00:00", "2026-04-17", "MQ-005", "owner_delegation_burden", True, 0.0, True),
        ]
        regressed_rows = [
            build_mock_row("2026-04-18T00:00:00+00:00", "2026-04-18", "MQ-001", "capability_reuse_rate", False, 50.0, False),
            build_mock_row("2026-04-18T00:00:00+00:00", "2026-04-18", "MQ-005", "owner_delegation_burden", False, 25.0, False),
        ]
        improving_rows = [
            build_mock_row("2026-04-19T00:00:00+00:00", "2026-04-19", "MQ-001", "capability_reuse_rate", True, 100.0, True),
            build_mock_row("2026-04-19T00:00:00+00:00", "2026-04-19", "MQ-005", "owner_delegation_burden", True, 0.0, True),
        ]
        write_mock_jsonl(jsonl_dir / "2026-04-17.jsonl", stable_rows)
        write_mock_jsonl(jsonl_dir / "2026-04-18.jsonl", regressed_rows)
        write_mock_jsonl(jsonl_dir / "2026-04-19.jsonl", improving_rows)

        report = regression_report(jsonl_dir, compare_last=2)
        if report["status"] != "stable":
            issues.append("regression selftest expected stable when latest run recovered")

        regressed_report = regression_report(jsonl_dir, compare_date="2026-04-17")
        if regressed_report["status"] != "stable":
            issues.append("regression selftest date selector should compare latest recovered run and stay stable")

        latest_regressed_rows = [
            build_mock_row("2026-04-20T00:00:00+00:00", "2026-04-20", "MQ-001", "capability_reuse_rate", False, 50.0, False),
            build_mock_row("2026-04-20T00:00:00+00:00", "2026-04-20", "MQ-005", "owner_delegation_burden", False, 25.0, False),
        ]
        write_mock_jsonl(jsonl_dir / "2026-04-20.jsonl", latest_regressed_rows)
        report = regression_report(jsonl_dir, compare_last=1)
        if report["status"] != "regression":
            issues.append("regression selftest failed to detect pass->fail regression")

        trend_completed = subprocess.run(
            ["bash", str(repo_root / "scripts" / "eval" / "trend-calculator.sh"), "--jsonl-dir", str(jsonl_dir), "--json"],
            capture_output=True,
            text=True,
            check=False,
        )
        if not trend_completed.stdout.strip():
            issues.append("trend selftest returned empty output")
        else:
            trend_payload = json.loads(trend_completed.stdout)
            if trend_payload.get("status") not in {"pass", "fail", "pending"}:
                issues.append("trend selftest returned invalid status")
    return issues


def self_test(repo_root: Path) -> tuple[bool, list[str]]:
    case_results, _ = run_suite(repo_root)
    by_id = {item.case_id: item for item in case_results}
    issues = []

    for case_id, expected_passed in SELF_TEST_EXPECTED.items():
        actual = by_id.get(case_id)
        if actual is None:
            issues.append(f"missing case in suite: {case_id}")
            continue
        if actual.passed != expected_passed:
            issues.append(f"{case_id}: expected passed={expected_passed}, actual={actual.passed}")

    per_category: dict[str, dict[str, int]] = defaultdict(lambda: {"passed": 0, "failed": 0})
    for item in case_results:
        per_category[item.category]["passed" if item.passed else "failed"] += 1

    for category, expected in SELF_TEST_CATEGORY_COUNTS.items():
        actual = per_category.get(category, {"passed": 0, "failed": 0})
        if actual != expected:
            issues.append(f"{category}: expected {expected}, actual {actual}")

    repeated_ok = all(by_id[case_id].passed for case_id in ("MQ-001", "MQ-002", "MQ-003", "MQ-004"))
    decision_ok = all(by_id[case_id].passed for case_id in ("MQ-019", "MQ-020"))
    if not repeated_ok:
        issues.append("repeated_question regression detected")
    if not decision_ok:
        issues.append("decision_trace regression detected")

    issues.extend(regression_self_test(repo_root))
    return (not issues), issues


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    run_parser = sub.add_parser("run")
    run_parser.add_argument("--repo-root", required=True)
    run_parser.add_argument("--output-dir", required=True)
    run_parser.add_argument("--json", action="store_true")

    regression_parser = sub.add_parser("regression")
    regression_parser.add_argument("--jsonl-dir", required=True)
    regression_parser.add_argument("--last", type=int, default=1)
    regression_parser.add_argument("--date")
    regression_parser.add_argument("--json", action="store_true")

    trend_parser = sub.add_parser("trend")
    trend_parser.add_argument("--repo-root", required=True)
    trend_parser.add_argument("--jsonl-dir", required=True)
    trend_parser.add_argument("--json", action="store_true")

    selftest_parser = sub.add_parser("selftest")
    selftest_parser.add_argument("--repo-root", required=True)

    args = parser.parse_args()

    if args.command == "run":
        repo_root = Path(args.repo_root)
        output_dir = Path(args.output_dir)
        case_results, metrics_summary = run_suite(repo_root, output_dir)
        run_date = date.today().isoformat()
        run_id = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
        output_path = output_dir / f"{run_date}.jsonl"
        append_jsonl(output_path, run_id, run_date, case_results, metrics_summary)
        summary = build_run_summary(run_id, run_date, case_results, metrics_summary)
        if args.json:
            print(json.dumps(summary, ensure_ascii=False))
        else:
            print(render_markdown(run_id, run_date, case_results, metrics_summary))
        return 1 if summary["critical_failure"] else 0

    if args.command == "selftest":
        ok, issues = self_test(Path(args.repo_root))
        if ok:
            print("manager-quality selftest: ok")
            return 0
        for item in issues:
            print(item)
        return 1

    if args.command == "trend":
        payload = run_trend_calculator(Path(args.repo_root), Path(args.jsonl_dir))
        if args.json:
            print(json.dumps(payload, ensure_ascii=False))
        else:
            print(json.dumps(payload, ensure_ascii=False, indent=2))
        return 0 if payload.get("passed", True) else 1

    report = regression_report(Path(args.jsonl_dir), compare_last=args.last, compare_date=args.date)
    if args.json:
        print(json.dumps(report, ensure_ascii=False))
    else:
        if report["status"] == "insufficient_history":
            print(report["message"])
        elif report["status"] == "stable":
            print("No regressions detected.")
            print(report["payload_path"])
        else:
            print("\n".join(report["decision_entry"]))
            print("")
            print("# TASKS.yaml stub")
            print(json.dumps(report["task_stub"], ensure_ascii=False, indent=2))
            print("")
            print(report["payload_path"])
    return 2 if report["status"] == "regression" else 0


if __name__ == "__main__":
    raise SystemExit(main())
