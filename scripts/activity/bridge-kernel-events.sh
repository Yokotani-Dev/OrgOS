#!/bin/bash
# scripts/activity/bridge-kernel-events.sh — import kernel events (orgos-event.v1)
# from the current repo's .ai/_machine/events/events-*.jsonl (legacy .ai/events fallback) into the Central Activity Ledger.
#
# - Converts: event_type -> "kernel", payload summary -> title,
#   origin_event_id -> original event_id, source -> "kernel-bridge"
# - Idempotent via cursor files: $STORE/cursors/<repo-key>.json (line counts per shard)
# - Best-effort: ALWAYS exits 0 (SessionStart hook safe). Errors go to $STORE/errors.log.
# - Store: $ORGOS_ACTIVITY_DIR or ~/.orgos/activity
# Self-contained: bash 3.2 + python3 stdlib only. Never sources other scripts/.

STORE="${ORGOS_ACTIVITY_DIR:-$HOME/.orgos/activity}"
export ORGOS_ACTIVITY_STORE="$STORE"

if ! command -v python3 >/dev/null 2>&1; then
  {
    mkdir -p "$STORE" 2>/dev/null && chmod 700 "$STORE" 2>/dev/null
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) bridge-kernel-events: python3 not found" >> "$STORE/errors.log"
  } 2>/dev/null
  exit 0
fi

python3 - <<'PYEOF' || true
import datetime
import glob
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile

STORE = os.environ.get("ORGOS_ACTIVITY_STORE") or os.path.expanduser("~/.orgos/activity")

# Keep in sync with log-event.sh and mcp-journal-server.py (tests/activity
# assert all three writers redact). Kernel payloads are arbitrary
# operator-supplied JSON, so everything we copy into the central ledger
# must pass through redact().
SECRET_PATTERNS = [
    r"AKIA[0-9A-Z]{16}",
    r"(?:ghp|gho|ghs|ghu)_[A-Za-z0-9]{36,}",
    r"github_pat_[A-Za-z0-9_]{22,}",
    r"sk-[A-Za-z0-9_-]{20,}",
    r"xox[baprs]-[A-Za-z0-9-]{10,}",
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----",
    r"(?i)(?:password|token|secret|api_key)[=:]\S{8,}",
]

ERRORS_LOG_MAX_BYTES = 5 * 1024 * 1024
ERROR_MSG_MAX_CHARS = 2000


def utc_now():
    return datetime.datetime.now(datetime.timezone.utc)


def ensure_dir(path):
    os.makedirs(path, mode=0o700, exist_ok=True)
    try:
        os.chmod(path, 0o700)
    except Exception:
        pass


def redact(text):
    if not text:
        return text
    for pat in SECRET_PATTERNS:
        text = re.sub(pat, "[REDACTED]", text)
    return text


def clean_text(text, limit, single_line=True):
    """redact -> (optionally) collapse whitespace -> truncate."""
    text = redact(str(text or ""))
    if single_line:
        text = " ".join(text.split())
    if len(text) > limit:
        text = text[: limit - 1] + "…"
    return text


def log_error(msg):
    try:
        ensure_dir(STORE)
        msg = clean_text(msg, ERROR_MSG_MAX_CHARS)
        path = os.path.join(STORE, "errors.log")
        try:
            if os.path.getsize(path) > ERRORS_LOG_MAX_BYTES:
                os.replace(path, path + ".1")
        except OSError:
            pass
        with open(path, "a", encoding="utf-8") as f:
            f.write("%s bridge-kernel-events: %s\n"
                    % (utc_now().strftime("%Y-%m-%dT%H:%M:%SZ"), msg))
    except Exception:
        pass


def git(args, cwd=None):
    try:
        r = subprocess.run(["git"] + args, capture_output=True, text=True,
                           timeout=5, cwd=cwd)
        if r.returncode == 0:
            return r.stdout.strip()
    except Exception:
        pass
    return ""


def normalize_remote(url):
    url = (url or "").strip()
    if not url:
        return ""
    if "://" in url:
        rest = url.split("://", 1)[1]
        if "/" in rest:
            hostport, path = rest.split("/", 1)
        else:
            hostport, path = rest, ""
        if "@" in hostport:
            hostport = hostport.rsplit("@", 1)[1]
        result = hostport + ("/" + path if path else "")
    else:
        m = re.match(r"^(?:[^@/]+@)?([^:/]+):(.+)$", url)
        if m:
            result = m.group(1) + "/" + m.group(2)
        else:
            result = url
    result = result.rstrip("/")
    if result.endswith(".git"):
        result = result[:-4]
    return result


def parse_ts(s):
    if not s:
        return None
    for fmt in ("%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S.%fZ"):
        try:
            return datetime.datetime.strptime(s, fmt).replace(
                tzinfo=datetime.timezone.utc)
        except ValueError:
            pass
    try:
        dt = datetime.datetime.fromisoformat(s)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=datetime.timezone.utc)
        return dt
    except Exception:
        return None


def summarize_payload(payload, limit=200):
    if not isinstance(payload, dict) or not payload:
        return ""
    parts = []
    for key in sorted(payload.keys()):
        val = payload[key]
        if isinstance(val, (dict, list)):
            val = json.dumps(val, ensure_ascii=False, sort_keys=True)
        parts.append("%s=%s" % (key, val))
    text = " ".join(parts)
    if len(text) > limit:
        text = text[: limit - 1] + "…"
    return text


def load_existing_origin_ids(repo_path):
    """Collect origin_event_ids already bridged for this repo from the
    central shards. Only used on the rare cursor-reset path, so that
    origin_event_id actually functions as the duplicate-prevention key
    (spec section 3) when a source file shrinks / rotates."""
    existing = set()
    for shard in glob.glob(os.path.join(STORE, "events-*.jsonl")):
        try:
            f = open(shard, "r", encoding="utf-8")
        except Exception:
            continue
        with f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    ev = json.loads(line)
                except Exception:
                    continue
                if not isinstance(ev, dict):
                    continue
                if str(ev.get("source") or "") != "kernel-bridge":
                    continue
                repo = ev.get("repo") if isinstance(ev.get("repo"), dict) else {}
                if str(repo.get("path") or "") != repo_path:
                    continue
                oid = str(ev.get("origin_event_id") or "")
                if oid:
                    existing.add(oid)
    return existing


def main():
    toplevel = git(["rev-parse", "--show-toplevel"])
    repo_path = toplevel or os.getcwd()
    repo_name = os.path.basename(repo_path.rstrip("/")) or repo_path
    remote = normalize_remote(git(["remote", "get-url", "origin"])) if toplevel else ""

    # Distributed-code dual-path: try the new _machine layout first, then the
    # legacy path so older clones still bridge correctly.
    events_dir = os.path.join(repo_path, ".ai", "_machine", "events")
    if not os.path.isdir(events_dir):
        events_dir = os.path.join(repo_path, ".ai", "events")
    if not os.path.isdir(events_dir):
        return  # nothing to bridge

    repo_key = "%s-%s" % (
        re.sub(r"[^A-Za-z0-9._-]", "_", repo_name),
        hashlib.sha256(repo_path.encode("utf-8")).hexdigest()[:8],
    )
    cursors_dir = os.path.join(STORE, "cursors")
    cursor_path = os.path.join(cursors_dir, "%s.json" % repo_key)
    cursor = {"repo_path": repo_path, "files": {}}
    try:
        with open(cursor_path, "r", encoding="utf-8") as f:
            loaded = json.load(f)
        if isinstance(loaded, dict) and isinstance(loaded.get("files"), dict):
            cursor["files"] = loaded["files"]
    except Exception:
        pass

    imported = 0
    known_origin_ids = None  # loaded lazily, only when a cursor reset happens
    for src in sorted(glob.glob(os.path.join(events_dir, "events-*.jsonl"))):
        fname = os.path.basename(src)
        state = cursor["files"].get(fname) or {}
        start_line = int(state.get("lines") or 0)
        last_event_id = str(state.get("last_event_id") or "")
        try:
            with open(src, "r", encoding="utf-8") as f:
                lines = f.readlines()
        except Exception as e:
            log_error("cannot read %s: %s" % (src, e))
            continue
        dedup_active = False
        if start_line > len(lines):
            # source file shrank / rotated; reset cursor for this file and
            # fall back to origin_event_id dedup so we never re-import.
            log_error("cursor beyond EOF for %s (cursor=%d lines=%d); resetting"
                      % (fname, start_line, len(lines)))
            start_line = 0
            last_event_id = ""
            if known_origin_ids is None:
                known_origin_ids = load_existing_origin_ids(repo_path)
            dedup_active = True
        lineno = start_line
        for raw in lines[start_line:]:
            lineno += 1
            raw = raw.strip()
            if not raw:
                continue
            try:
                kev = json.loads(raw)
            except Exception:
                log_error("skip malformed line %s:%d" % (fname, lineno))
                continue
            if not isinstance(kev, dict):
                continue
            origin_id = str(kev.get("event_id") or "")
            if dedup_active and origin_id and origin_id in known_origin_ids:
                last_event_id = origin_id
                continue
            kev_type = str(kev.get("event_type") or "")
            task_id = str(kev.get("task_id") or "")
            ts_dt = parse_ts(str(kev.get("ts") or "")) or utc_now()
            ts = ts_dt.strftime("%Y-%m-%dT%H:%M:%SZ")
            actor = kev.get("actor") if isinstance(kev.get("actor"), dict) else {}
            title = kev_type or "kernel event"
            if task_id:
                title = "%s %s" % (title, task_id)
            detail = summarize_payload(kev.get("payload"))

            event = {
                "schema_version": "orgos-activity.v1",
                "event_id": "ACT-%s-%s" % (ts_dt.strftime("%Y%m%dT%H%M%SZ"),
                                           os.urandom(4).hex()),
                "ts": ts,
                "repo": {"name": repo_name, "path": repo_path, "remote": remote},
                "branch": "",
                "session_id": "",
                "actor": {"role": clean_text(str(actor.get("role") or "system"), 100),
                          "id": clean_text(str(actor.get("id") or "kernel"), 100)},
                "event_type": "kernel",
                "task_id": clean_text(task_id, 100),
                "title": clean_text(title, 500),
                "detail": clean_text(detail, 2000),
                "source": "kernel-bridge",
                "origin_event_id": origin_id,
            }
            ensure_dir(STORE)
            shard = os.path.join(STORE, "events-%s.jsonl" % ts_dt.strftime("%Y%m"))
            line = json.dumps(event, sort_keys=True, ensure_ascii=False) + "\n"
            fd = os.open(shard, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
            try:
                os.write(fd, line.encode("utf-8"))
            finally:
                os.close(fd)
            imported += 1
            last_event_id = origin_id
            if known_origin_ids is not None and origin_id:
                known_origin_ids.add(origin_id)
        cursor["files"][fname] = {"lines": len(lines),
                                  "last_event_id": last_event_id}

    # Persist cursor (atomic replace).
    ensure_dir(STORE)
    ensure_dir(cursors_dir)
    tmp_fd, tmp_path = tempfile.mkstemp(dir=cursors_dir, prefix=".cursor.")
    try:
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
            json.dump(cursor, f, sort_keys=True, ensure_ascii=False, indent=2)
        os.replace(tmp_path, cursor_path)
    except Exception:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass
        raise

    if imported:
        sys.stdout.write("bridge-kernel-events: imported %d event(s)\n" % imported)


try:
    main()
except Exception as exc:
    # exception type + sanitized message only (no raw tracebacks / argv,
    # which may carry attacker-influenced or secret-bearing strings)
    log_error("%s: %s" % (type(exc).__name__, exc))
sys.exit(0)
PYEOF
exit 0
