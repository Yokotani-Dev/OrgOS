#!/usr/bin/env python3
"""OWNER_INBOX decision-card helpers."""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys
import tempfile
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]
OWNER_INBOX = REPO_ROOT / ".ai" / "OWNER_INBOX.md"
SCHEMA_FILE = REPO_ROOT / ".claude" / "schemas" / "decision-card.yaml"

HIGH_HEADING = "## 高優先度決済 (response < 24h 推奨)"
MEDIUM_HEADING = "## 中優先度決済 (response < 7d)"
LOW_HEADING = "## 低優先度決済 (response < 30d)"
ARCHIVED_HEADING = "## Archived (resolved or expired)"
PRIORITY_HEADINGS = (HIGH_HEADING, MEDIUM_HEADING, LOW_HEADING)

TYPE_ALIASES = {
    "type_a": "type_a_direction",
    "type_b": "type_b_preference",
    "type_c": "type_c_authentication",
    "type_d": "type_d_notification",
}
RECOMMENDATION_BY_KEY = {
    "A": "APPROVE",
    "B": "DEFER",
    "C": "REJECT",
}
RESOLVED_STATUSES = {"approved", "rejected", "auto_applied", "expired"}

CARD_RE = re.compile(
    r"(?ms)^### (?P<title>[^\n]+)\n(?P<preamble>.*?)"
    r"^```decision-card\n(?P<yaml>.*?)\n```\n?"
)
SECTION_RE = re.compile(r"(?m)^## .+$")


class InboxError(Exception):
    pass


@dataclass
class CardBlock:
    data: dict[str, Any]
    section: str
    raw: str
    start: int
    end: int


def fail(message: str) -> None:
    raise InboxError(message)


def load_text() -> str:
    if not OWNER_INBOX.exists():
        fail(f"missing OWNER_INBOX: {OWNER_INBOX.relative_to(REPO_ROOT)}")
    return OWNER_INBOX.read_text(encoding="utf-8")


def write_text_atomic(text: str) -> None:
    fd, tmp_name = tempfile.mkstemp(
        prefix=".OWNER_INBOX.",
        suffix=".tmp",
        dir=str(OWNER_INBOX.parent),
        text=True,
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
        os.replace(tmp_name, OWNER_INBOX)
    except Exception:
        try:
            os.unlink(tmp_name)
        except FileNotFoundError:
            pass
        raise


def load_schema() -> dict[str, Any]:
    if not SCHEMA_FILE.exists():
        fail(f"missing schema: {SCHEMA_FILE.relative_to(REPO_ROOT)}")
    with SCHEMA_FILE.open(encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def parse_iso8601(value: Any, field_name: str = "deadline") -> datetime:
    if isinstance(value, datetime):
        parsed = value
    elif isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            fail(f"{field_name} is not ISO8601: {value}")
    else:
        fail(f"{field_name} must be ISO8601 string")

    if parsed.tzinfo is None:
        parsed = parsed.astimezone()
    return parsed


def iso_now() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def normalize_type(value: str) -> str:
    return TYPE_ALIASES.get(value, value)


def schema_field(schema: dict[str, Any], field: str) -> dict[str, Any]:
    value = schema.get("fields", {}).get(field, {})
    return value if isinstance(value, dict) else {}


def validate_card(card: dict[str, Any], schema: dict[str, Any]) -> None:
    fields = schema.get("fields", {})
    for name, spec in fields.items():
        if isinstance(spec, dict) and spec.get("required") and name not in card:
            fail(f"decision-card missing required field: {name}")

    id_pattern = schema_field(schema, "id").get("pattern")
    if id_pattern and not re.fullmatch(id_pattern, str(card.get("id", ""))):
        fail(f"decision-card id does not match schema: {card.get('id')}")

    for name in ("type", "recommendation", "risk", "default_if_no_response", "status"):
        enum = schema_field(schema, name).get("enum")
        if enum and name in card and card[name] not in enum:
            fail(f"decision-card field {name} is outside schema enum: {card[name]}")

    for name in ("decision", "recommendation_reason"):
        if not isinstance(card.get(name), str) or not card[name].strip():
            fail(f"decision-card field {name} must be a non-empty string")

    parse_iso8601(card.get("deadline"), "deadline")
    if "resolved_at" in card and card["resolved_at"] is not None:
        parse_iso8601(card["resolved_at"], "resolved_at")

    options = card.get("options")
    if not isinstance(options, list) or not options:
        fail("decision-card options must be a non-empty array")

    recommended_options = []
    for option in options:
        if not isinstance(option, dict):
            fail("decision-card option must be an object")
        for key in ("key", "label", "consequence", "is_recommended"):
            if key not in option:
                fail(f"decision-card option missing field: {key}")
        if not isinstance(option["is_recommended"], bool):
            fail("decision-card option is_recommended must be boolean")
        if option["is_recommended"]:
            recommended_options.append(option)
    if len(recommended_options) != 1:
        fail("decision-card must have exactly one recommended option")

    judgment = card.get("synthetic_owner_judgment")
    if judgment is not None:
        if not isinstance(judgment, dict):
            fail("synthetic_owner_judgment must be an object")
        verdict = judgment.get("verdict")
        allowed = schema_field(schema, "synthetic_owner_judgment").get("fields", {}).get(
            "verdict", {}
        ).get("enum", [])
        if verdict not in allowed:
            fail(f"synthetic_owner_judgment.verdict is invalid: {verdict}")
        confidence = judgment.get("confidence")
        if not isinstance(confidence, (int, float)) or not 0.0 <= confidence <= 1.0:
            fail("synthetic_owner_judgment.confidence must be 0.0..1.0")


def section_for_offset(text: str, offset: int) -> str:
    section = ""
    for match in SECTION_RE.finditer(text):
        if match.start() > offset:
            break
        section = match.group(0)
    return section


def parse_cards(text: str) -> list[CardBlock]:
    cards: list[CardBlock] = []
    for match in CARD_RE.finditer(text):
        try:
            data = yaml.safe_load(match.group("yaml")) or {}
        except yaml.YAMLError as exc:
            fail(f"failed to parse decision-card YAML near byte {match.start()}: {exc}")
        if not isinstance(data, dict):
            fail(f"decision-card YAML is not an object near byte {match.start()}")
        cards.append(
            CardBlock(
                data=data,
                section=section_for_offset(text, match.start()),
                raw=match.group(0).rstrip(),
                start=match.start(),
                end=match.end(),
            )
        )
    return cards


def generate_card_block(card: dict[str, Any], archived: bool = False) -> str:
    recommended_key = recommended_option(card).get("key", "?")
    if archived:
        answer_line = "- 回答: archived のため不要"
    elif card.get("status", "pending") == "pending":
        answer_line = f'- 回答: `echo "{card["id"]} <A|B|C>" >> .ai/OWNER_COMMENTS.md`'
    else:
        answer_line = "- 回答: resolved のため不要"
    card_yaml = yaml.safe_dump(
        card,
        allow_unicode=True,
        sort_keys=False,
        default_flow_style=False,
        width=1000,
    ).rstrip()
    return (
        f"### {card['id']} [{card['type']}] {card['decision']}\n"
        f"- 推奨選択: {recommended_key}\n"
        f"{answer_line}\n\n"
        "```decision-card\n"
        f"{card_yaml}\n"
        "```"
    )


def recommended_option(card: dict[str, Any]) -> dict[str, Any]:
    for option in card.get("options", []):
        if option.get("is_recommended"):
            return option
    return {}


def priority_heading_for_card(card: dict[str, Any]) -> str:
    risk = card.get("risk")
    if risk in {"high", "critical"}:
        return HIGH_HEADING
    if risk == "medium":
        return MEDIUM_HEADING
    return LOW_HEADING


def generate_id(text: str, now: datetime) -> str:
    prefix = f"D-{now.date().isoformat()}-"
    max_n = 0
    for match in re.finditer(r"\bD-\d{4}-\d{2}-\d{2}-(\d{3})\b", text):
        full = match.group(0)
        if full.startswith(prefix):
            max_n = max(max_n, int(match.group(1)))
    return f"{prefix}{max_n + 1:03d}"


def replace_section_content(text: str, heading: str, content: str) -> str:
    pattern = re.compile(rf"(?ms)^{re.escape(heading)}\n(?P<body>.*?)(?=^## |\Z)")
    match = pattern.search(text)
    if not match:
        fail(f"missing section: {heading}")
    replacement = f"{heading}\n\n{content.strip()}\n\n"
    return text[: match.start()] + replacement + text[match.end() :]


def render_priority_content(cards: list[dict[str, Any]]) -> str:
    if not cards:
        return "(なし)"
    return "\n\n".join(generate_card_block(card) for card in cards)


def archive_original(card: dict[str, Any]) -> str:
    source = card.get("source")
    if not isinstance(source, dict):
        return "-"
    original = str(source.get("original_id", "-"))
    request_id = source.get("request_id")
    if request_id:
        return f"{original} / {request_id}"
    return original


def markdown_cell(value: Any) -> str:
    text = "" if value is None else str(value)
    return text.replace("|", "\\|").replace("\n", " ")


def render_archive_table(cards: list[dict[str, Any]]) -> str:
    lines = [
        "| id | original | decision | recommendation | risk | default | status | resolved_at |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for card in cards:
        lines.append(
            "| "
            + " | ".join(
                markdown_cell(value)
                for value in (
                    card.get("id"),
                    archive_original(card),
                    card.get("decision"),
                    card.get("recommendation"),
                    card.get("risk"),
                    card.get("default_if_no_response"),
                    card.get("status"),
                    card.get("resolved_at", ""),
                )
            )
            + " |"
        )
    return "\n".join(lines)


def render_archived_content(cards: list[dict[str, Any]]) -> str:
    table = render_archive_table(cards)
    if not cards:
        return table
    return table + "\n\n" + "\n\n".join(generate_card_block(card, archived=True) for card in cards)


def rebuild_console(
    text: str,
    high_cards: list[dict[str, Any]],
    medium_cards: list[dict[str, Any]],
    low_cards: list[dict[str, Any]],
    archived_cards: list[dict[str, Any]],
) -> str:
    first_heading = text.find(HIGH_HEADING)
    if first_heading < 0:
        fail(f"missing section: {HIGH_HEADING}")
    prefix = text[:first_heading].rstrip() + "\n\n"
    parts = [
        prefix.rstrip(),
        HIGH_HEADING,
        "",
        render_priority_content(high_cards),
        "",
        MEDIUM_HEADING,
        "",
        render_priority_content(medium_cards),
        "",
        LOW_HEADING,
        "",
        render_priority_content(low_cards),
        "",
        ARCHIVED_HEADING,
        "",
        render_archived_content(archived_cards),
        "",
    ]
    return "\n".join(parts)


def normalize_options(raw_json: str, recommended_key: str) -> tuple[list[dict[str, Any]], str]:
    try:
        options = json.loads(raw_json)
    except json.JSONDecodeError as exc:
        fail(f"--options must be valid JSON: {exc}")
    if not isinstance(options, list) or not options:
        fail("--options must be a non-empty JSON array")

    normalized = []
    recommendation = ""
    for option in options:
        if not isinstance(option, dict):
            fail("--options entries must be objects")
        item = {
            "key": str(option.get("key", "")).strip(),
            "label": str(option.get("label", "")).strip(),
            "consequence": str(option.get("consequence", "")).strip(),
            "is_recommended": False,
        }
        if not item["key"] or not item["label"] or not item["consequence"]:
            fail("--options entries require key, label, and consequence")
        item["is_recommended"] = item["key"] == recommended_key
        if item["is_recommended"]:
            label_upper = item["label"].upper()
            recommendation = (
                label_upper
                if label_upper in set(RECOMMENDATION_BY_KEY.values())
                else RECOMMENDATION_BY_KEY.get(recommended_key, "")
            )
        normalized.append(item)

    if not recommendation:
        fail(f"--recommendation key not found in options: {recommended_key}")
    return normalized, recommendation


def add_decision(args: argparse.Namespace) -> None:
    schema = load_schema()
    text = load_text()
    now = datetime.now().astimezone()
    decision_id = generate_id(text, now)
    recommended_key = args.recommendation.upper()
    options, recommendation = normalize_options(args.options, recommended_key)
    card = {
        "id": decision_id,
        "type": normalize_type(args.type),
        "decision": args.decision,
        "recommendation": recommendation,
        "recommendation_reason": args.recommendation_reason
        or f"Option {recommended_key} is recommended by add-decision.sh input.",
        "risk": args.risk,
        "options": options,
        "default_if_no_response": args.default_if_no_response,
        "deadline": parse_iso8601(args.deadline).isoformat(timespec="seconds"),
        "status": "pending",
    }
    validate_card(card, schema)
    block = generate_card_block(card)
    heading = priority_heading_for_card(card)
    pattern = re.compile(rf"(?ms)^{re.escape(heading)}\n(?P<body>.*?)(?=^## |\Z)")
    match = pattern.search(text)
    if not match:
        fail(f"missing section: {heading}")
    body = match.group("body").strip()
    new_body = block if body in {"", "(なし)"} else f"{body}\n\n{block}"
    write_text_atomic(replace_section_content(text, heading, new_body))
    print(decision_id)


def pending_cards(cards: list[CardBlock]) -> list[dict[str, Any]]:
    return [
        card.data
        for card in cards
        if card.section != ARCHIVED_HEADING and card.data.get("status", "pending") == "pending"
    ]


def days_remaining(deadline: Any, now: datetime) -> int:
    parsed = parse_iso8601(deadline)
    return math.ceil((parsed - now).total_seconds() / 86400)


def list_pending(args: argparse.Namespace) -> None:
    schema = load_schema()
    text = load_text()
    cards = parse_cards(text)
    for card in cards:
        validate_card(card.data, schema)

    now = datetime.now().astimezone()
    rows = []
    for card in pending_cards(cards):
        option = recommended_option(card)
        rows.append(
            {
                "id": card.get("id"),
                "decision": card.get("decision"),
                "recommendation": f"{option.get('key')}/{card.get('recommendation')}",
                "risk": card.get("risk"),
                "deadline": card.get("deadline"),
                "days_remaining": days_remaining(card.get("deadline"), now),
            }
        )

    if args.json:
        print(json.dumps(rows, ensure_ascii=False, indent=2))
        return

    headers = ["id", "decision", "recommendation", "risk", "deadline", "残日数"]
    table_rows = [
        [
            str(row["id"]),
            str(row["decision"]),
            str(row["recommendation"]),
            str(row["risk"]),
            str(row["deadline"]),
            str(row["days_remaining"]),
        ]
        for row in rows
    ]
    widths = [
        max([len(headers[index])] + [len(row[index]) for row in table_rows])
        for index in range(len(headers))
    ]
    print(" | ".join(headers[index].ljust(widths[index]) for index in range(len(headers))))
    print("-+-".join("-" * width for width in widths))
    if table_rows:
        for row in table_rows:
            print(" | ".join(row[index].ljust(widths[index]) for index in range(len(headers))))
    else:
        print("(0 pending decisions)")


def split_cards_by_section(cards: list[CardBlock]) -> dict[str, list[dict[str, Any]]]:
    grouped = {heading: [] for heading in (*PRIORITY_HEADINGS, ARCHIVED_HEADING)}
    for card in cards:
        if card.section in grouped:
            grouped[card.section].append(card.data)
    return grouped


def log_lines(lines: list[str], log_path: str | None) -> None:
    for line in lines:
        print(line)
    if log_path:
        target = Path(log_path)
        if not target.is_absolute():
            target = REPO_ROOT / target
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("a", encoding="utf-8") as handle:
            for line in lines:
                handle.write(line + "\n")


def expire_old(args: argparse.Namespace) -> None:
    schema = load_schema()
    text = load_text()
    cards = parse_cards(text)
    grouped = split_cards_by_section(cards)
    now = datetime.now().astimezone()
    now_text = now.isoformat(timespec="seconds")
    logs = []

    for heading in PRIORITY_HEADINGS:
        remaining = []
        for card in grouped[heading]:
            validate_card(card, schema)
            if card.get("status", "pending") != "pending":
                remaining.append(card)
                continue
            deadline = parse_iso8601(card.get("deadline"))
            if deadline >= now:
                remaining.append(card)
                continue

            default = card.get("default_if_no_response")
            if default == "auto_apply":
                card["status"] = "auto_applied"
                card["resolved_at"] = now_text
                card["synthetic_owner_judgment"] = {
                    "verdict": "approve",
                    "confidence": 1.0,
                }
                remaining.append(card)
                logs.append(f"{now_text} {card['id']} auto_applied")
            elif default == "defer_7d":
                card["deadline"] = (now + timedelta(days=7)).isoformat(timespec="seconds")
                remaining.append(card)
                logs.append(f"{now_text} {card['id']} deferred_7d")
            elif default == "escalate":
                if heading == HIGH_HEADING:
                    remaining.append(card)
                else:
                    grouped[HIGH_HEADING].append(card)
                logs.append(f"{now_text} {card['id']} escalated")
            elif default == "no_op":
                card["status"] = "expired"
                card["resolved_at"] = now_text
                remaining.append(card)
                logs.append(f"{now_text} {card['id']} expired")
            else:
                fail(f"{card.get('id')} has invalid default_if_no_response: {default}")
        grouped[heading] = remaining

    for heading in PRIORITY_HEADINGS:
        deduped = []
        seen = set()
        for card in grouped[heading]:
            card_id = card.get("id")
            if card_id in seen:
                continue
            seen.add(card_id)
            validate_card(card, schema)
            deduped.append(card)
        grouped[heading] = deduped

    if logs:
        new_text = rebuild_console(
            text,
            grouped[HIGH_HEADING],
            grouped[MEDIUM_HEADING],
            grouped[LOW_HEADING],
            grouped[ARCHIVED_HEADING],
        )
        write_text_atomic(new_text)
    else:
        logs.append(f"{now_text} no expired pending decisions")
    log_lines(logs, args.log)


def archive_cards(args: argparse.Namespace) -> None:
    schema = load_schema()
    text = load_text()
    cards = parse_cards(text)
    grouped = split_cards_by_section(cards)
    archived = grouped[ARCHIVED_HEADING]
    moved = []

    for heading in PRIORITY_HEADINGS:
        remaining = []
        for card in grouped[heading]:
            validate_card(card, schema)
            if card.get("status") in RESOLVED_STATUSES:
                if not card.get("resolved_at"):
                    card["resolved_at"] = iso_now()
                archived.append(card)
                moved.append(card.get("id"))
            else:
                remaining.append(card)
        grouped[heading] = remaining

    for card in archived:
        validate_card(card, schema)

    if moved:
        new_text = rebuild_console(
            text,
            grouped[HIGH_HEADING],
            grouped[MEDIUM_HEADING],
            grouped[LOW_HEADING],
            archived,
        )
        write_text_atomic(new_text)
        for card_id in moved:
            print(f"archived {card_id}")
    else:
        print("no resolved decisions to archive")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="inbox",
        description="Manage .ai/OWNER_INBOX.md decision cards.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    add = subparsers.add_parser("add", help="append a pending decision card")
    add.add_argument("--type", required=True, help="type_a/b/c/d or schema type")
    add.add_argument("--decision", required=True, help="one-line decision text")
    add.add_argument("--recommendation", required=True, choices=["A", "B", "C", "a", "b", "c"])
    add.add_argument("--risk", required=True, choices=["low", "medium", "high"])
    add.add_argument("--options", required=True, help="JSON option array")
    add.add_argument("--deadline", required=True, help="ISO8601 deadline")
    add.add_argument(
        "--default-if-no-response",
        default="no_op",
        choices=["auto_apply", "defer_7d", "escalate", "no_op"],
        help="default action when deadline expires (default: no_op)",
    )
    add.add_argument("--recommendation-reason", default="", help="schema recommendation_reason")
    add.set_defaults(func=add_decision)

    list_cmd = subparsers.add_parser("list", help="list pending decision cards")
    list_cmd.add_argument("--json", action="store_true", help="emit JSON")
    list_cmd.set_defaults(func=list_pending)

    expire = subparsers.add_parser("expire", help="process overdue pending decision cards")
    expire.add_argument("--log", help="optional log file path; stdout is always written")
    expire.set_defaults(func=expire_old)

    archive = subparsers.add_parser("archive", help="move resolved cards to Archived")
    archive.set_defaults(func=archive_cards)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        args.func(args)
    except InboxError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
