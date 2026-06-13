#!/usr/bin/env python3
"""Append an OrgOS program event to the monthly hash-chained JSONL ledger."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import re
import secrets
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SCHEMA_VERSION = "orgos-event.v1"
GENESIS_HASH = "0" * 64
EVENT_TYPES = {
    "TaskCreated",
    "TaskUpdated",
    "LeaseAcquired",
    "LeaseReleased",
    "LeaseExpired",
    "WorkerStarted",
    "WorkerFinished",
    "WorkerFailed",
    "ArtifactCollected",
    "ArtifactCollectionFailed",
    "VerificationPassed",
    "VerificationFailed",
    "IntegrationRequested",
    "CommitIntegrated",
    "PolicyViolationDetected",
}
ACTOR_ROLES = {
    "manager",
    "claude",
    "codex",
    "subagent",
    "integrator",
    "owner",
    "system",
    "mock",
}
HASH_RE = re.compile(r"^[a-f0-9]{64}$")
EVENT_ID_RE = re.compile(r"^EVT-[0-9]{8}T[0-9]{6}Z-[A-Za-z0-9._-]+-[a-f0-9]{8}$")


class EventAppendError(Exception):
    """User-facing append failure."""


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_ts(raw_ts: str) -> datetime:
    value = raw_ts.strip()
    if value.endswith("Z"):
        value = f"{value[:-1]}+00:00"
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError as exc:
        raise EventAppendError(f"invalid --ts value: {raw_ts}") from exc
    if parsed.tzinfo is None:
        raise EventAppendError("--ts must include timezone information")
    return parsed.astimezone(timezone.utc).replace(microsecond=0)


def iso_from_datetime(value: datetime) -> str:
    return value.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def compact_ts(value: datetime) -> str:
    return value.astimezone(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def event_month(value: datetime) -> str:
    return value.astimezone(timezone.utc).strftime("%Y%m")


def safe_id_part(value: str) -> str:
    safe = re.sub(r"[^A-Za-z0-9._-]+", "-", value.strip())
    return safe.strip("-") or "event"


def find_repo_root(start: Path) -> Path:
    current = start.resolve()
    for candidate in (current, *current.parents):
        if (candidate / ".git").exists() or (candidate / "scripts" / "org").is_dir():
            return candidate
    return current


def parse_payload(raw_payload: str) -> dict[str, Any]:
    if raw_payload == "-":
        raw_payload = sys.stdin.read()
    try:
        payload = json.loads(raw_payload)
    except json.JSONDecodeError as exc:
        raise EventAppendError(f"payload JSON is invalid: {exc}") from exc
    if not isinstance(payload, dict):
        raise EventAppendError("payload must be a JSON object")
    return payload


def canonical_json_bytes(event: dict[str, Any]) -> bytes:
    return json.dumps(event, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def event_hash(event_without_hash: dict[str, Any]) -> str:
    return hashlib.sha256(canonical_json_bytes(event_without_hash)).hexdigest()


def read_last_event(path: Path) -> dict[str, Any] | None:
    if not path.is_file():
        return None

    last_line: str | None = None
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            stripped = line.strip()
            if stripped:
                last_line = stripped

    if last_line is None:
        return None

    try:
        event = json.loads(last_line)
    except json.JSONDecodeError as exc:
        raise EventAppendError(f"last event in {path} is invalid JSON: {exc}") from exc
    if not isinstance(event, dict):
        raise EventAppendError(f"last event in {path} must be a JSON object")
    validate_stored_event(event, source=str(path))
    return event


def latest_event_file(events_dir: Path) -> Path | None:
    files = sorted(events_dir.glob("events-[0-9][0-9][0-9][0-9][0-9][0-9].jsonl"))
    return files[-1] if files else None


def previous_hash_for_append(events_dir: Path, target_path: Path) -> str:
    latest_path = latest_event_file(events_dir)
    if latest_path is None:
        return GENESIS_HASH
    if latest_path.name > target_path.name:
        raise EventAppendError(
            f"refusing to append to older event period {target_path.name}; latest period is {latest_path.name}"
        )
    last_event = read_last_event(latest_path)
    if last_event is None:
        return GENESIS_HASH
    return str(last_event["hash"])


def build_actor(args: argparse.Namespace) -> dict[str, str]:
    if args.actor_role not in ACTOR_ROLES:
        raise EventAppendError(f"invalid actor role: {args.actor_role}")
    if not args.actor_id:
        raise EventAppendError("--actor-id is required")

    actor = {"role": args.actor_role, "id": args.actor_id}
    if args.actor_session_id:
        actor["session_id"] = args.actor_session_id
    if args.actor_model:
        actor["model"] = args.actor_model
    return actor


def build_event(args: argparse.Namespace, prev_hash: str) -> dict[str, Any]:
    if args.event_type not in EVENT_TYPES:
        raise EventAppendError(f"invalid event type: {args.event_type}")
    if not args.task_id:
        raise EventAppendError("--task-id is required")
    if not HASH_RE.match(prev_hash):
        raise EventAppendError("previous hash is invalid")

    ts_dt = parse_ts(args.ts) if args.ts else parse_ts(utc_now_iso())
    event_id = args.event_id or (
        f"EVT-{compact_ts(ts_dt)}-{safe_id_part(args.task_id)}-{secrets.token_hex(4)}"
    )

    event: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "event_id": event_id,
        "ts": iso_from_datetime(ts_dt),
        "event_type": args.event_type,
        "task_id": args.task_id,
        "actor": build_actor(args),
        "payload": parse_payload(args.payload_json),
        "prev_hash": prev_hash,
    }
    event["hash"] = event_hash({key: value for key, value in event.items() if key != "hash"})
    validate_stored_event(event, source="new event")
    return event


def validate_stored_event(event: dict[str, Any], *, source: str) -> None:
    required = {"event_id", "ts", "event_type", "task_id", "actor", "payload", "prev_hash", "hash"}
    missing = sorted(required.difference(event))
    if missing:
        raise EventAppendError(f"{source} missing required field(s): {', '.join(missing)}")
    if event.get("schema_version", SCHEMA_VERSION) != SCHEMA_VERSION:
        raise EventAppendError(f"{source} has invalid schema_version")
    if not isinstance(event.get("event_id"), str) or not EVENT_ID_RE.match(str(event["event_id"])):
        raise EventAppendError(f"{source} has invalid event_id")
    parse_ts(str(event["ts"]))
    if event.get("event_type") not in EVENT_TYPES:
        raise EventAppendError(f"{source} has invalid event_type")
    if not isinstance(event.get("task_id"), str) or not event["task_id"]:
        raise EventAppendError(f"{source} has invalid task_id")
    if not isinstance(event.get("payload"), dict):
        raise EventAppendError(f"{source} has invalid payload")
    actor = event.get("actor")
    if not isinstance(actor, dict):
        raise EventAppendError(f"{source} has invalid actor")
    if actor.get("role") not in ACTOR_ROLES or not isinstance(actor.get("id"), str) or not actor["id"]:
        raise EventAppendError(f"{source} has invalid actor role/id")
    if not isinstance(event.get("prev_hash"), str) or not HASH_RE.match(str(event["prev_hash"])):
        raise EventAppendError(f"{source} has invalid prev_hash")
    if not isinstance(event.get("hash"), str) or not HASH_RE.match(str(event["hash"])):
        raise EventAppendError(f"{source} has invalid hash")
    expected = event_hash({key: value for key, value in event.items() if key != "hash"})
    if event["hash"] != expected:
        raise EventAppendError(f"{source} hash does not match event contents")


def fsync_directory(path: Path) -> None:
    try:
        dir_fd = os.open(str(path), os.O_RDONLY)
    except OSError:
        return
    try:
        os.fsync(dir_fd)
    finally:
        os.close(dir_fd)


def append_event(events_dir: Path, event_ts: datetime, args: argparse.Namespace) -> tuple[Path, dict[str, Any]]:
    events_dir.mkdir(parents=True, exist_ok=True)
    lock_path = events_dir / ".events.lock"
    target_path = events_dir / f"events-{event_month(event_ts)}.jsonl"

    with lock_path.open("a+", encoding="utf-8") as lock_handle:
        fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX)
        prev_hash = previous_hash_for_append(events_dir, target_path)
        event = build_event(args, prev_hash)
        line = canonical_json_bytes(event) + b"\n"

        fd = os.open(str(target_path), os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)
        try:
            os.write(fd, line)
            os.fsync(fd)
        finally:
            os.close(fd)
        fsync_directory(events_dir)
        return target_path, event


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--event-type", required=True, choices=sorted(EVENT_TYPES))
    parser.add_argument("--task-id", required=True)
    parser.add_argument("--actor-role", required=True, choices=sorted(ACTOR_ROLES))
    parser.add_argument("--actor-id", required=True)
    parser.add_argument("--actor-session-id")
    parser.add_argument("--actor-model")
    parser.add_argument("--payload-json", default="{}")
    parser.add_argument("--ts", help="Event timestamp, ISO 8601 with timezone. Defaults to current UTC.")
    parser.add_argument("--event-id")
    parser.add_argument("--events-dir", help="Defaults to <repo>/.ai/_machine/events")
    parser.add_argument("--repo-root", help="Repository root used when --events-dir is omitted")
    return parser


def main(argv: list[str]) -> int:
    parser = build_parser()
    args = parser.parse_args(argv[1:])

    try:
        if not args.ts:
            args.ts = utc_now_iso()
        event_ts = parse_ts(args.ts)
        repo_root = Path(args.repo_root).resolve() if args.repo_root else find_repo_root(Path.cwd())
        events_dir = Path(args.events_dir).resolve() if args.events_dir else repo_root / ".ai" / "_machine" / "events"
        _, event = append_event(events_dir, event_ts, args)
    except EventAppendError as exc:
        print(f"append-event.py: {exc}", file=sys.stderr)
        return 1
    except OSError as exc:
        print(f"append-event.py: I/O error: {exc}", file=sys.stderr)
        return 1

    print(json.dumps(event, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
