#!/bin/bash
# scripts/activity/log-event.sh — Central Activity Ledger writer (schema: orgos-activity.v1)
#
# Usage:
#   log-event.sh --type <event_type> --title <text> [--task-id T-XXX] [--detail <text>]
#                [--actor-role manager] [--actor-id claude-manager] [--source cli]
#                [--stdin-hook]   # hook mode: extract session_id from stdin JSON
#
# Store: $ORGOS_ACTIVITY_DIR or ~/.orgos/activity
# Self-contained: bash 3.2 + python3 stdlib only. Never sources other scripts/.
# ALWAYS exits 0 (hook-safe). Errors go to $STORE/errors.log.

STORE="${ORGOS_ACTIVITY_DIR:-$HOME/.orgos/activity}"
export ORGOS_ACTIVITY_STORE="$STORE"

# Read stdin ONLY when --stdin-hook is present (and stdin is not a TTY).
ORGOS_HOOK_STDIN=""
_want_stdin=0
for _arg in "$@"; do
  if [ "$_arg" = "--stdin-hook" ]; then
    _want_stdin=1
  fi
done
if [ "$_want_stdin" = "1" ] && [ ! -t 0 ]; then
  ORGOS_HOOK_STDIN="$(cat 2>/dev/null || true)"
fi
export ORGOS_HOOK_STDIN

if ! command -v python3 >/dev/null 2>&1; then
  {
    mkdir -p "$STORE" 2>/dev/null && chmod 700 "$STORE" 2>/dev/null
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) log-event: python3 not found" >> "$STORE/errors.log"
  } 2>/dev/null
  exit 0
fi

python3 - "$@" <<'PYEOF' || true
import datetime
import json
import os
import re
import subprocess
import sys
import tempfile

STORE = os.environ.get("ORGOS_ACTIVITY_STORE") or os.path.expanduser("~/.orgos/activity")

EVENT_TYPES = ("session_start", "session_end", "task_created", "task_done",
               "decision", "note", "thought", "commit", "tick", "release", "kernel")
SOURCES = ("hook", "cli", "kernel-bridge")

SECRET_PATTERNS = [
    r"AKIA[0-9A-Z]{16}",
    r"(?:ghp|gho|ghs|ghu)_[A-Za-z0-9]{36,}",
    r"github_pat_[A-Za-z0-9_]{22,}",
    r"sk-[A-Za-z0-9_-]{20,}",
    r"xox[baprs]-[A-Za-z0-9-]{10,}",
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----",
    r"(?i)(?:password|token|secret|api_key)[=:]\S{8,}",
]


def utc_now():
    return datetime.datetime.now(datetime.timezone.utc)


def ensure_store():
    os.makedirs(STORE, mode=0o700, exist_ok=True)
    try:
        os.chmod(STORE, 0o700)
    except Exception:
        pass


ERRORS_LOG_MAX_BYTES = 5 * 1024 * 1024
ERROR_MSG_MAX_CHARS = 2000


def redact(text):
    if not text:
        return text
    for pat in SECRET_PATTERNS:
        text = re.sub(pat, "[REDACTED]", text)
    return text


def clean_text(text, limit, single_line=True):
    """redact -> (optionally) collapse whitespace -> truncate.

    Keeps every serialized event line safely under the 4KB practical
    append-atomicity bound (spec section 3) and the ledger single-line."""
    text = redact(str(text or ""))
    if single_line:
        text = " ".join(text.split())
    if len(text) > limit:
        text = text[: limit - 1] + "…"
    return text


def log_error(msg):
    try:
        ensure_store()
        msg = clean_text(msg, ERROR_MSG_MAX_CHARS)
        path = os.path.join(STORE, "errors.log")
        try:
            if os.path.getsize(path) > ERRORS_LOG_MAX_BYTES:
                os.replace(path, path + ".1")
        except OSError:
            pass
        with open(path, "a", encoding="utf-8") as f:
            f.write("%s log-event: %s\n" % (utc_now().strftime("%Y-%m-%dT%H:%M:%SZ"), msg))
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
    """Normalize remote URL to host/path without scheme or credentials."""
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


def parse_args(argv):
    opts = {"type": None, "title": None, "task-id": "", "detail": "",
            "actor-role": "manager", "actor-id": "claude-manager",
            "source": "cli", "stdin-hook": False}
    valued = ("type", "title", "task-id", "detail", "actor-role", "actor-id", "source")
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--stdin-hook":
            opts["stdin-hook"] = True
            i += 1
            continue
        if a.startswith("--") and a[2:] in valued:
            if i + 1 >= len(argv):
                raise ValueError("missing value for %s" % a)
            opts[a[2:]] = argv[i + 1]
            i += 2
            continue
        raise ValueError("unknown argument: %s" % a)
    return opts


def main():
    opts = parse_args(sys.argv[1:])
    if not opts["type"]:
        raise ValueError("--type is required")
    if opts["type"] not in EVENT_TYPES:
        raise ValueError("invalid --type %r (allowed: %s)"
                         % (opts["type"], " ".join(EVENT_TYPES)))
    if opts["title"] is None:
        raise ValueError("--title is required")
    if opts["source"] not in SOURCES:
        raise ValueError("invalid --source %r (allowed: %s)"
                         % (opts["source"], " ".join(SOURCES)))

    session_id = ""
    if opts["stdin-hook"]:
        raw = os.environ.get("ORGOS_HOOK_STDIN", "")
        if raw.strip():
            try:
                payload = json.loads(raw)
                if isinstance(payload, dict):
                    session_id = str(payload.get("session_id") or "")
            except Exception as e:
                log_error("stdin-hook JSON parse failed: %s" % e)

    toplevel = git(["rev-parse", "--show-toplevel"])
    repo_path = toplevel or os.getcwd()
    repo_name = os.path.basename(repo_path.rstrip("/")) or repo_path
    remote = normalize_remote(git(["remote", "get-url", "origin"])) if toplevel else ""
    branch = git(["branch", "--show-current"]) if toplevel else ""

    now = utc_now()
    ts = now.strftime("%Y-%m-%dT%H:%M:%SZ")
    event = {
        "schema_version": "orgos-activity.v1",
        "event_id": "ACT-%s-%s" % (now.strftime("%Y%m%dT%H%M%SZ"), os.urandom(4).hex()),
        "ts": ts,
        "repo": {"name": repo_name, "path": repo_path, "remote": remote},
        "branch": branch,
        "session_id": session_id,
        "actor": {"role": opts["actor-role"], "id": opts["actor-id"]},
        "event_type": opts["type"],
        "task_id": opts["task-id"],
        "title": clean_text(opts["title"], 500),
        "detail": clean_text(opts["detail"], 2000, single_line=False),
        "source": opts["source"],
        "origin_event_id": "",
    }

    ensure_store()
    shard = os.path.join(STORE, "events-%s.jsonl" % now.strftime("%Y%m"))
    line = json.dumps(event, sort_keys=True, ensure_ascii=False) + "\n"
    fd = os.open(shard, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        os.write(fd, line.encode("utf-8"))
    finally:
        os.close(fd)

    # Upsert repos.json (atomic replace).
    repos_path = os.path.join(STORE, "repos.json")
    repos = {}
    try:
        with open(repos_path, "r", encoding="utf-8") as f:
            loaded = json.load(f)
        if isinstance(loaded, dict):
            repos = loaded
    except Exception:
        repos = {}
    repos[repo_name] = {"path": repo_path, "remote": remote, "last_seen": ts}
    tmp_fd, tmp_path = tempfile.mkstemp(dir=STORE, prefix=".repos.json.")
    try:
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
            json.dump(repos, f, sort_keys=True, ensure_ascii=False, indent=2)
        os.replace(tmp_path, repos_path)
    except Exception:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass
        raise


try:
    main()
except Exception as exc:
    # exception type + sanitized message only (no raw tracebacks / argv,
    # which may carry mis-quoted secret-bearing strings)
    log_error("%s: %s" % (type(exc).__name__, exc))
sys.exit(0)
PYEOF
exit 0
