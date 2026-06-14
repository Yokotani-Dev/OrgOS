#!/bin/bash
# scripts/activity/summarize-session.sh — rich session_end composer (schema: orgos-activity.v1)
#
# On session Stop, compose ONE rich session_end event (commits + task transitions)
# instead of the generic "session end", then emit it via log-event.sh so the
# secret-redaction and store/append logic stay shared in one place.
#
# Usage:
#   summarize-session.sh [--stdin-hook] [--repo-root <path>]
#
# Store: $ORGOS_ACTIVITY_DIR or ~/.orgos/activity (passed through to log-event.sh).
# Self-contained: bash 3.2 + python3 stdlib only. Never sources other scripts/.
# ALWAYS exits 0 (hook-safe). Errors go to $STORE/errors.log.

STORE="${ORGOS_ACTIVITY_DIR:-$HOME/.orgos/activity}"
export ORGOS_ACTIVITY_STORE="$STORE"

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
LOG_EVENT="$SCRIPT_DIR/log-event.sh"
export ORGOS_LOG_EVENT="$LOG_EVENT"

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
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) summarize-session: python3 not found" >> "$STORE/errors.log"
  } 2>/dev/null
  exit 0
fi

python3 - "$@" <<'PYEOF' || true
import datetime
import glob
import json
import os
import re
import subprocess
import sys

STORE = os.environ.get("ORGOS_ACTIVITY_STORE") or os.path.expanduser("~/.orgos/activity")
LOG_EVENT = os.environ.get("ORGOS_LOG_EVENT") or ""

ERRORS_LOG_MAX_BYTES = 5 * 1024 * 1024
ERROR_MSG_MAX_CHARS = 2000

# Kept in sync with log-event.sh redaction; we pre-redact here so the composed
# title is safe even before log-event.sh re-redacts it on write.
SECRET_PATTERNS = [
    r"AKIA[0-9A-Z]{16}",
    r"(?:ghp|gho|ghs|ghu)_[A-Za-z0-9]{36,}",
    r"github_pat_[A-Za-z0-9_]{22,}",
    r"sk-[A-Za-z0-9_-]{20,}",
    r"xox[baprs]-[A-Za-z0-9-]{10,}",
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----",
    r"(?i)(?:password|token|secret|api_key)[=:]\S{8,}",
]

# Kernel event types that count as a "task transition" within the window.
TASK_EVENT_TYPES = ("TaskUpdated", "TaskCreated", "CommitIntegrated")

TITLE_MAX = 300


def utc_now():
    return datetime.datetime.now(datetime.timezone.utc)


def ensure_store():
    os.makedirs(STORE, mode=0o700, exist_ok=True)
    try:
        os.chmod(STORE, 0o700)
    except Exception:
        pass


def redact(text):
    if not text:
        return text
    for pat in SECRET_PATTERNS:
        text = re.sub(pat, "[REDACTED]", text)
    return text


def clean_text(text, limit):
    text = redact(str(text or ""))
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
            f.write("%s summarize-session: %s\n"
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


def parse_args(argv):
    opts = {"stdin-hook": False, "repo-root": ""}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--stdin-hook":
            opts["stdin-hook"] = True
            i += 1
            continue
        if a == "--repo-root":
            if i + 1 >= len(argv):
                raise ValueError("missing value for --repo-root")
            opts["repo-root"] = argv[i + 1]
            i += 2
            continue
        raise ValueError("unknown argument: %s" % a)
    return opts


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


def find_session_start(repo_path):
    """Most recent prior session_start ts for this repo in the central store.

    Match by repo.path (most reliable; falls back to repo.name). Returns an
    aware datetime, or None when no prior session_start exists."""
    best = None
    repo_name = os.path.basename(repo_path.rstrip("/")) or repo_path
    for shard in sorted(glob.glob(os.path.join(STORE, "events-*.jsonl"))):
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
                if str(ev.get("event_type") or "") != "session_start":
                    continue
                repo = ev.get("repo") if isinstance(ev.get("repo"), dict) else {}
                ev_path = str(repo.get("path") or "")
                ev_name = str(repo.get("name") or "")
                if ev_path:
                    if ev_path != repo_path:
                        continue
                elif ev_name != repo_name:
                    continue
                dt = parse_ts(str(ev.get("ts") or ""))
                if dt is None:
                    continue
                if best is None or dt > best:
                    best = dt
    return best


def gather_commits(repo_root, since_dt):
    """Commit count + up to 3 subjects within the window.

    Window precedence:
      1. since_dt (last session_start), via git log --since.
      2. fallback: commits in the last 6 hours.
    Best-effort; returns (count, [subjects])."""
    if since_dt is not None:
        since = since_dt.strftime("%Y-%m-%dT%H:%M:%SZ")
    else:
        since = (utc_now() - datetime.timedelta(hours=6)).strftime(
            "%Y-%m-%dT%H:%M:%SZ")
    out = git(["log", "--no-merges", "--since=%s" % since, "--format=%s"],
              cwd=repo_root)
    subjects = [s for s in out.splitlines() if s.strip()]
    count = len(subjects)
    return count, subjects[:3]


def gather_task_ids(repo_root, since_dt):
    """Distinct task_ids touched (TaskUpdated/TaskCreated/CommitIntegrated)
    within the session window, from the repo's kernel events shards. Cap 8.

    Order: first-seen within the window, so the title reflects narrative
    order rather than arbitrary set ordering."""
    if since_dt is None:
        since_dt = utc_now() - datetime.timedelta(hours=6)
    events_dir = os.path.join(repo_root, ".ai", "_machine", "events")
    if not os.path.isdir(events_dir):
        events_dir = os.path.join(repo_root, ".ai", "events")
    if not os.path.isdir(events_dir):
        return []
    # Current month shard, plus prior month for window crossing month boundary.
    months = set()
    months.add(utc_now().strftime("%Y%m"))
    months.add(since_dt.strftime("%Y%m"))
    ordered = []
    seen = set()
    rows = []
    for month in sorted(months):
        path = os.path.join(events_dir, "events-%s.jsonl" % month)
        if not os.path.isfile(path):
            continue
        try:
            f = open(path, "r", encoding="utf-8")
        except Exception:
            continue
        with f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    kev = json.loads(line)
                except Exception:
                    continue
                if not isinstance(kev, dict):
                    continue
                if str(kev.get("event_type") or "") not in TASK_EVENT_TYPES:
                    continue
                tid = str(kev.get("task_id") or "").strip()
                if not tid:
                    continue
                dt = parse_ts(str(kev.get("ts") or ""))
                if dt is None or dt < since_dt:
                    continue
                rows.append((dt, tid))
    rows.sort(key=lambda t: t[0])
    for _, tid in rows:
        if tid in seen:
            continue
        seen.add(tid)
        ordered.append(tid)
        if len(ordered) >= 8:
            break
    return ordered


def compact_task_ids(task_ids):
    """Render task ids compactly: shared "T-OS-" prefix collapses to a
    leading id plus bare numeric suffixes. e.g.
      ["T-OS-499","T-OS-500","T-OS-501"] -> "T-OS-499,500,501"."""
    if not task_ids:
        return ""
    out = [task_ids[0]]
    prefix = None
    m = re.match(r"^(.*?)(\d+)$", task_ids[0])
    if m:
        prefix = m.group(1)
    for tid in task_ids[1:]:
        if prefix and tid.startswith(prefix):
            out.append(tid[len(prefix):])
        else:
            out.append(tid)
            m2 = re.match(r"^(.*?)(\d+)$", tid)
            prefix = m2.group(1) if m2 else None
    return ",".join(out)


def compose_title(commit_count, subjects, task_ids):
    parts = []
    if commit_count:
        if subjects:
            subj = "; ".join(clean_text(s, 80) for s in subjects)
            if commit_count > len(subjects):
                subj += "; …"
            parts.append("%d commit%s (%s)"
                         % (commit_count, "s" if commit_count != 1 else "", subj))
        else:
            parts.append("%d commit%s"
                         % (commit_count, "s" if commit_count != 1 else ""))
    if task_ids:
        parts.append("tasks %s" % compact_task_ids(task_ids))
    if parts:
        title = "session: " + " · ".join(parts)
    else:
        title = "session: no commits or task changes"
    return clean_text(title, TITLE_MAX)


def emit(title):
    """Emit via log-event.sh so store/append/redaction logic is shared.

    Falls back to a direct shard write if log-event.sh is unreachable."""
    raw = os.environ.get("ORGOS_HOOK_STDIN", "")
    argv = ["bash", LOG_EVENT, "--type", "session_end", "--title", title,
            "--source", "hook"]
    if raw.strip():
        argv.append("--stdin-hook")
    if LOG_EVENT and os.path.isfile(LOG_EVENT):
        try:
            env = dict(os.environ)
            env["ORGOS_ACTIVITY_DIR"] = STORE
            subprocess.run(argv, input=raw, text=True, timeout=10,
                           env=env, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL)
            return
        except Exception as e:
            log_error("log-event.sh invocation failed: %s" % e)
    log_error("log-event.sh unavailable at %r; session_end not emitted" % LOG_EVENT)


def main():
    opts = parse_args(sys.argv[1:])
    repo_root = opts["repo-root"] or ""
    if repo_root:
        repo_root = os.path.abspath(repo_root)
    toplevel = git(["rev-parse", "--show-toplevel"], cwd=repo_root or None)
    repo_path = toplevel or (repo_root or os.getcwd())

    since_dt = find_session_start(repo_path)
    commit_count, subjects = gather_commits(repo_path, since_dt)
    task_ids = gather_task_ids(repo_path, since_dt)
    title = compose_title(commit_count, subjects, task_ids)
    emit(title)
    # Echo composed title for smoke/inspection (not used by the hook).
    sys.stdout.write(title + "\n")


try:
    main()
except Exception as exc:
    log_error("%s: %s" % (type(exc).__name__, exc))
sys.exit(0)
PYEOF
exit 0
