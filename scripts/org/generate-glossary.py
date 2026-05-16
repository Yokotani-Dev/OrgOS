#!/usr/bin/env python3
"""Generate an OrgOS glossary from rules and kernel synthesis documents."""
from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path


DEFAULT_OUTPUT = Path(".ai/GLOSSARY.generated.md")
DEFAULT_SYNTHESIS = Path(".ai/REVIEW/T-OS-400/SYNTHESIS.md")


@dataclass(frozen=True)
class TermDefinition:
    term: str
    patterns: tuple[str, ...]
    description: str


TERM_DEFINITIONS: tuple[TermDefinition, ...] = (
    TermDefinition(
        "Allowed Paths",
        ("allowed_paths", "allowed paths"),
        "The explicit file or directory set a worker may modify; writes outside it must be blocked or treated as out of scope.",
    ),
    TermDefinition(
        "Artifact Manifest",
        ("artifact manifest", "artifact_manifest"),
        "A durable record of task outputs that must exist before cleanup or done-state transitions can be trusted.",
    ),
    TermDefinition(
        "Authority Boundary",
        ("authority boundary", "AUTHORITY_BOUNDARY"),
        "The documented limit of who may approve or perform privileged actions, including OS mutation and irreversible operations.",
    ),
    TermDefinition(
        "Autonomy Level",
        ("autonomy_level", "autonomy levels"),
        "A runtime execution boundary used after authority checks to decide how independently an agent may act.",
    ),
    TermDefinition(
        "Capability Boundary",
        ("capability boundary", "capability boundaries"),
        "The physical and procedural limit that keeps workers inside the tools, paths, and operations granted for a task.",
    ),
    TermDefinition(
        "Capability Preflight",
        ("capability preflight",),
        "A pre-execution check that selects verified local capabilities and flags high-risk operations before ad-hoc commands are used.",
    ),
    TermDefinition(
        "Cleanup Fail-Closed",
        ("cleanup fail-closed", "fail-closed"),
        "A cleanup rule where missing or invalid preservation evidence stops deletion and preserves the worktree for inspection.",
    ),
    TermDefinition(
        "Codex Worker",
        ("Codex worker", "Codex"),
        "An implementation or quality-review worker that operates under work orders, allowed paths, and task-scoped evidence requirements.",
    ),
    TermDefinition(
        "Constitutional Invariant",
        ("constitutional invariant", "invariant"),
        "A compact kernel rule that must be enforced by runtime checks rather than only documented as natural-language policy.",
    ),
    TermDefinition(
        "Context Pack",
        ("context pack",),
        "A bounded, redacted bundle of task, rule, result, and artifact context used to hand relevant state to workers.",
    ),
    TermDefinition(
        "Decision",
        ("decision", "DECISIONS"),
        "A recorded choice or planning update that preserves rationale, tradeoffs, and downstream effects for future sessions.",
    ),
    TermDefinition(
        "Domain Constraint",
        ("domain constraint", "domain_category"),
        "A confirmed rule from law, platform policy, or project domain knowledge that gates design and implementation.",
    ),
    TermDefinition(
        "Durable Artifact",
        ("durable artifact",),
        "A task output that survives worker cleanup and can be audited by the Manager, integrator, or later reviewers.",
    ),
    TermDefinition(
        "Event Log",
        ("event log", "EVENTS.jsonl"),
        "The append-only source of truth for operational events; projections may be generated from it but should not replace it.",
    ),
    TermDefinition(
        "Handoff Packet",
        ("handoff packet", "handoff"),
        "A structured completion report containing status, changed files, assumptions, verification, and downstream impacts.",
    ),
    TermDefinition(
        "Integrator",
        ("integrator", "Integrator-Only Commit"),
        "The dedicated integration role or script that is allowed to turn reviewed task work into commits.",
    ),
    TermDefinition(
        "Iron Law",
        ("iron law",),
        "A non-negotiable operating rule that must be reflected in workflow checks, gates, or enforcement scripts.",
    ),
    TermDefinition(
        "Journey",
        ("journey", "current_flow", "target_flow"),
        "The user's current and target workflow, including happy paths and error paths, used to derive implementation requirements.",
    ),
    TermDefinition(
        "Kill List",
        ("kill list",),
        "A consolidation mechanism for retiring excess rules, tasks, or agents so the operating system stops growing by patch-on-patch.",
    ),
    TermDefinition(
        "Lease",
        ("lease", "Lease Before Write"),
        "A time- or task-scoped write authority that must exist before files are edited.",
    ),
    TermDefinition(
        "Manager",
        ("manager", "control-plane dispatcher"),
        "The control-plane dispatcher responsible for planning, delegation, and coordination; raw commits are outside this role.",
    ),
    TermDefinition(
        "Owner",
        ("owner", "Owner Approval"),
        "The human authority for irreversible decisions, production approval, secrets, budget, legal commitments, and unresolved tradeoffs.",
    ),
    TermDefinition(
        "Per-Task Worktree",
        ("per-task worktree", "worktree"),
        "An isolated checkout used for one implementation task so worker edits and cleanup are scoped.",
    ),
    TermDefinition(
        "Plan Contract",
        ("plan contract",),
        "The Owner-facing plan artifact that turns intent into an approve, modify, or reject decision point.",
    ),
    TermDefinition(
        "Policy Core",
        ("policy_core.py", "policy core"),
        "A central pure-function enforcement layer for kernel invariants and deterministic policy decisions.",
    ),
    TermDefinition(
        "Posttool",
        ("posttool", "post-exec", "posttool HEAD auditor"),
        "A post-execution check that audits changes, HEAD movement, artifacts, or policy violations after a worker action.",
    ),
    TermDefinition(
        "Pretool",
        ("pretool", "pre-exec"),
        "A pre-execution check that blocks forbidden commands or writes before the action reaches the tool or shell.",
    ),
    TermDefinition(
        "Projection",
        ("projection", "generated views"),
        "A generated read model derived from the event log, such as dashboards or generated task views.",
    ),
    TermDefinition(
        "Protected Branch",
        ("protected branch", "main/develop"),
        "A branch such as main or develop that workers and managers must not directly mutate.",
    ),
    TermDefinition(
        "Quality Contract",
        ("quality contract", "quality_level"),
        "A confirmed definition of done across functionality, error handling, security, performance, observability, and documentation.",
    ),
    TermDefinition(
        "Request Intake Loop",
        ("request intake loop",),
        "The ordered process for binding a new request to memory, capability checks, active work, and next-step decisions.",
    ),
    TermDefinition(
        "Rule Consolidation",
        ("rule consolidation", "rule", "consolidation"),
        "The process of reducing overlapping natural-language rules into a smaller enforced kernel.",
    ),
    TermDefinition(
        "Secret Management",
        ("secret management", "secrets"),
        "The policy that keeps credentials out of repository files and uses approved secret stores or redacted pointers.",
    ),
    TermDefinition(
        "SSOT",
        ("SSOT", "source of truth"),
        "Single source of truth; in kernel-v2 this points to the event log rather than scattered operational ledgers.",
    ),
    TermDefinition(
        "State Mutation",
        ("state mutation", "State Mutation via Org Tool"),
        "A change to operational state that must go through approved org tooling instead of direct ledger edits.",
    ),
    TermDefinition(
        "Threat Model",
        ("threat model", "THREAT_MODEL"),
        "A pre-implementation artifact identifying abuse cases, failure modes, security risks, and mitigation expectations.",
    ),
)


class GlossaryError(Exception):
    pass


def read_sources(repo_root: Path, rules_dir: Path, synthesis_path: Path) -> tuple[str, list[Path]]:
    paths: list[Path] = []
    resolved_rules_dir = rules_dir if rules_dir.is_absolute() else repo_root / rules_dir
    resolved_synthesis = synthesis_path if synthesis_path.is_absolute() else repo_root / synthesis_path

    if resolved_rules_dir.exists():
        paths.extend(sorted(resolved_rules_dir.glob("*.md")))
    if resolved_synthesis.exists():
        paths.append(resolved_synthesis)
    if not paths:
        raise GlossaryError("no source documents found")

    chunks: list[str] = []
    for path in paths:
        chunks.append(path.read_text(encoding="utf-8", errors="replace"))
    return "\n".join(chunks), paths


def term_is_present(corpus: str, term_definition: TermDefinition) -> bool:
    for pattern in term_definition.patterns:
        if re.search(re.escape(pattern), corpus, flags=re.IGNORECASE):
            return True
    return False


def build_glossary(corpus: str) -> list[tuple[str, str]]:
    entries: dict[str, str] = {}
    for term_definition in TERM_DEFINITIONS:
        if term_is_present(corpus, term_definition):
            entries[term_definition.term] = term_definition.description

    return sorted(entries.items(), key=lambda item: item[0].casefold())


def render_glossary(entries: list[tuple[str, str]], source_paths: list[Path], repo_root: Path) -> str:
    if not entries:
        raise GlossaryError("no glossary terms extracted")

    relative_sources = []
    for path in source_paths:
        try:
            relative_sources.append(path.relative_to(repo_root).as_posix())
        except ValueError:
            relative_sources.append(path.as_posix())

    lines = [
        "# OrgOS Glossary (generated)",
        "",
        "> Generated by `scripts/org/generate-glossary.py`.",
        f"> Sources: {len(relative_sources)} documents from `.claude/rules/*.md` and `.ai/REVIEW/T-OS-400/SYNTHESIS.md`.",
        "",
    ]
    for term, description in entries:
        lines.append(f"- **{term}**: {description}")
    lines.append("")
    return "\n".join(lines)


def generate(repo_root: Path, rules_dir: Path, synthesis_path: Path, output_path: Path) -> int:
    corpus, source_paths = read_sources(repo_root, rules_dir, synthesis_path)
    entries = build_glossary(corpus)
    rendered = render_glossary(entries, source_paths, repo_root)

    resolved_output = output_path if output_path.is_absolute() else repo_root / output_path
    resolved_output.parent.mkdir(parents=True, exist_ok=True)
    resolved_output.write_text(rendered, encoding="utf-8")
    print(f"generated {len(entries)} glossary term(s) at {resolved_output}")
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", default=".", help="repository root (default: current directory)")
    parser.add_argument("--rules-dir", default=".claude/rules", help="rules directory under repo root")
    parser.add_argument(
        "--synthesis",
        default=str(DEFAULT_SYNTHESIS),
        help="kernel synthesis markdown path under repo root",
    )
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT), help="output markdown path")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    try:
        return generate(
            Path(args.repo_root).resolve(),
            Path(args.rules_dir),
            Path(args.synthesis),
            Path(args.output),
        )
    except GlossaryError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
