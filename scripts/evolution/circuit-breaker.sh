#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
STATE_FILE="${ORGOS_CIRCUIT_BREAKER_STATE:-$REPO_ROOT/.ai/EVOLUTION/circuit-breaker.yaml}"

usage() {
  cat <<'EOF'
Usage: bash scripts/evolution/circuit-breaker.sh <command> [reason]

Commands:
  check             Exit 0 when the breaker allows apply, exit 1 when open/tripped.
  increment-apply   Increment apply counters and trip if a configured apply limit is reached.
  increment-revert  Increment consecutive revert counter and trip at threshold.
  reset-cycle       Reset current_cycle_apply_count.
  reset-daily       Reset today_apply_count.
  trip <reason>     Manually open the breaker.
  restore           Owner restore: close breaker and reset counters.
EOF
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 64
fi

ACTION="$1"
shift

case "$ACTION" in
  check|increment-apply|increment-revert|reset-cycle|reset-daily|restore) ;;
  trip)
    if [[ $# -lt 1 || -z "${1:-}" ]]; then
      echo "trip requires a reason" >&2
      exit 64
    fi
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown command: $ACTION" >&2
    usage >&2
    exit 64
    ;;
esac

export REPO_ROOT STATE_FILE ACTION

python3 - "$@" <<'PY'
from __future__ import annotations

import copy
import json
import os
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import yaml

state_path = Path(os.environ["STATE_FILE"])
action = os.environ["ACTION"]
args = sys.argv[1:]

DEFAULT_STATE: dict[str, Any] = {
    "version": "1.0",
    "limits": {
        "max_apply_per_cycle": 3,
        "max_apply_per_day": 10,
        "consecutive_revert_threshold": 3,
        "scheduler_timeout_minutes": 30,
    },
    "state": {
        "current_cycle_apply_count": 0,
        "today_apply_count": 0,
        "consecutive_revert_count": 0,
        "last_apply_at": None,
        "breaker_state": "closed",
        "tripped_at": None,
        "trip_reason": None,
    },
}


def utc_now() -> datetime:
    override = os.environ.get("ORGOS_CIRCUIT_BREAKER_NOW")
    if override:
        try:
            return datetime.fromisoformat(override.replace("Z", "+00:00")).astimezone(timezone.utc)
        except ValueError:
            print(
                json.dumps(
                    {
                        "level": "error",
                        "trace": "circuit_breaker",
                        "event": "failed",
                        "error_class": "invalid_argument",
                        "message": "ORGOS_CIRCUIT_BREAKER_NOW is not ISO8601",
                        "recovery": "Unset it or pass an ISO8601 timestamp.",
                    },
                    ensure_ascii=False,
                    sort_keys=True,
                )
            )
            raise SystemExit(64)
    return datetime.now(timezone.utc).replace(microsecond=0)


def ts() -> str:
    return utc_now().isoformat().replace("+00:00", "Z")


def log(level: str, event: str, **fields: Any) -> None:
    payload = {
        "level": level,
        "trace": "circuit_breaker",
        "event": event,
        "at": ts(),
    }
    payload.update(fields)
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))


def merge_defaults(data: dict[str, Any]) -> dict[str, Any]:
    merged = copy.deepcopy(DEFAULT_STATE)
    if isinstance(data.get("version"), str):
        merged["version"] = data["version"]
    if isinstance(data.get("limits"), dict):
        merged["limits"].update(data["limits"])
    if isinstance(data.get("state"), dict):
        merged["state"].update(data["state"])
    return normalize(merged)


def normalize(data: dict[str, Any]) -> dict[str, Any]:
    limits = data["limits"]
    state = data["state"]
    for key in ("max_apply_per_cycle", "max_apply_per_day", "consecutive_revert_threshold", "scheduler_timeout_minutes"):
        limits[key] = int(limits.get(key) or DEFAULT_STATE["limits"][key])
        if limits[key] < 1:
            limits[key] = DEFAULT_STATE["limits"][key]
    for key in ("current_cycle_apply_count", "today_apply_count", "consecutive_revert_count"):
        state[key] = max(0, int(state.get(key) or 0))
    if state.get("breaker_state") not in {"closed", "half_open", "open"}:
        state["breaker_state"] = "closed"
    for key in ("last_apply_at", "tripped_at", "trip_reason"):
        if state.get(key) == "":
            state[key] = None
    return data


def load() -> dict[str, Any]:
    if not state_path.exists():
        return copy.deepcopy(DEFAULT_STATE)
    try:
        data = yaml.safe_load(state_path.read_text(encoding="utf-8")) or {}
    except yaml.YAMLError as exc:
        log(
            "error",
            "failed",
            error_class="invalid_state",
            message=f"circuit breaker state is invalid YAML: {exc}",
            recovery="Repair .ai/EVOLUTION/circuit-breaker.yaml or run restore after Owner review.",
        )
        raise SystemExit(65)
    if not isinstance(data, dict):
        log(
            "error",
            "failed",
            error_class="invalid_state",
            message="circuit breaker state is not an object",
            recovery="Repair .ai/EVOLUTION/circuit-breaker.yaml or run restore after Owner review.",
        )
        raise SystemExit(65)
    return merge_defaults(data)


def save(data: dict[str, Any]) -> None:
    state_path.parent.mkdir(parents=True, exist_ok=True)
    rendered = yaml.safe_dump(data, sort_keys=False, allow_unicode=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=state_path.parent, delete=False) as handle:
        handle.write(rendered)
        tmp_path = Path(handle.name)
    tmp_path.replace(state_path)


def state_summary(data: dict[str, Any]) -> dict[str, Any]:
    state = data["state"]
    limits = data["limits"]
    return {
        "breaker_state": state["breaker_state"],
        "current_cycle_apply_count": state["current_cycle_apply_count"],
        "max_apply_per_cycle": limits["max_apply_per_cycle"],
        "today_apply_count": state["today_apply_count"],
        "max_apply_per_day": limits["max_apply_per_day"],
        "consecutive_revert_count": state["consecutive_revert_count"],
        "consecutive_revert_threshold": limits["consecutive_revert_threshold"],
        "last_apply_at": state["last_apply_at"],
        "tripped_at": state["tripped_at"],
        "trip_reason": state["trip_reason"],
    }


def trip(data: dict[str, Any], reason: str) -> None:
    state = data["state"]
    state["breaker_state"] = "open"
    state["tripped_at"] = ts()
    state["trip_reason"] = reason


def enforce_limits(data: dict[str, Any]) -> bool:
    state = data["state"]
    limits = data["limits"]
    if state["breaker_state"] == "open":
        return False
    if state["current_cycle_apply_count"] >= limits["max_apply_per_cycle"]:
        trip(data, f"max_apply_per_cycle reached ({state['current_cycle_apply_count']}/{limits['max_apply_per_cycle']})")
        save(data)
        return False
    if state["today_apply_count"] >= limits["max_apply_per_day"]:
        trip(data, f"max_apply_per_day reached ({state['today_apply_count']}/{limits['max_apply_per_day']})")
        save(data)
        return False
    return True


def main() -> None:
    data = load()
    state = data["state"]
    limits = data["limits"]

    if action == "check":
        if enforce_limits(data):
            log("info", "check_passed", state=state_summary(data))
            return
        log("error", "check_blocked", error_class="circuit_breaker_open", recovery="Owner review must restore the breaker before automatic apply resumes.", state=state_summary(data))
        raise SystemExit(1)

    if action == "increment-apply":
        if state["breaker_state"] == "open":
            log("error", "increment_apply_blocked", error_class="circuit_breaker_open", recovery="Owner review must restore the breaker before automatic apply resumes.", state=state_summary(data))
            raise SystemExit(1)
        state["current_cycle_apply_count"] += 1
        state["today_apply_count"] += 1
        state["last_apply_at"] = ts()
        if state["current_cycle_apply_count"] >= limits["max_apply_per_cycle"]:
            trip(data, f"max_apply_per_cycle reached ({state['current_cycle_apply_count']}/{limits['max_apply_per_cycle']})")
            event = "apply_limit_tripped"
            level = "warn"
        elif state["today_apply_count"] >= limits["max_apply_per_day"]:
            trip(data, f"max_apply_per_day reached ({state['today_apply_count']}/{limits['max_apply_per_day']})")
            event = "apply_limit_tripped"
            level = "warn"
        else:
            event = "apply_incremented"
            level = "info"
        save(data)
        log(level, event, state=state_summary(data))
        return

    if action == "increment-revert":
        state["consecutive_revert_count"] += 1
        if state["consecutive_revert_count"] >= limits["consecutive_revert_threshold"]:
            trip(data, f"consecutive_revert_threshold reached ({state['consecutive_revert_count']}/{limits['consecutive_revert_threshold']})")
            event = "revert_limit_tripped"
            level = "warn"
        else:
            event = "revert_incremented"
            level = "info"
        save(data)
        log(level, event, state=state_summary(data))
        return

    if action == "reset-cycle":
        state["current_cycle_apply_count"] = 0
        save(data)
        log("info", "cycle_reset", state=state_summary(data))
        return

    if action == "reset-daily":
        state["today_apply_count"] = 0
        save(data)
        log("info", "daily_reset", state=state_summary(data))
        return

    if action == "trip":
        reason = " ".join(args).strip()
        trip(data, reason)
        save(data)
        log("warn", "manual_trip", state=state_summary(data))
        return

    if action == "restore":
        restored = copy.deepcopy(DEFAULT_STATE)
        restored["limits"] = data["limits"]
        save(restored)
        log("info", "restored", state=state_summary(restored))
        return

    log("error", "failed", error_class="invalid_argument", message=f"unknown command: {action}", recovery="Use --help.")
    raise SystemExit(64)


main()
PY
