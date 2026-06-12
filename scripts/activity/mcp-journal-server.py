#!/usr/bin/env python3
"""scripts/activity/mcp-journal-server.py — Central Activity Ledger MCP server.

stdio MCP server (JSON-RPC 2.0, newline-delimited) exposing the central store
(~/.orgos/activity, or $ORGOS_ACTIVITY_DIR) to any MCP client.

Tools:
  - journal_get(date?, days?, format?)            -> daily digest (md | json)
  - activity_search(query?, repo?, type?, days?)  -> cross-repo event search (JSON)
  - activity_log(type, title, detail?, task_id?)  -> append an event from anywhere

Self-contained: python3 stdlib only. Never crashes on bad input; always answers
with a JSON-RPC error instead.
"""

import datetime
import json
import os
import re
import subprocess
import sys
import tempfile

STORE = os.environ.get("ORGOS_ACTIVITY_DIR") or os.path.expanduser("~/.orgos/activity")

PROTOCOL_VERSION = "2024-11-05"
SERVER_INFO = {"name": "orgos-journal", "version": "1.0.0"}

EVENT_TYPES = ("session_start", "session_end", "task_created", "task_done",
               "decision", "note", "thought", "commit", "tick", "release", "kernel")
THOUGHT_TYPES = ("decision", "note", "thought")

SECRET_PATTERNS = [
    r"AKIA[0-9A-Z]{16}",
    r"(?:ghp|gho|ghs|ghu)_[A-Za-z0-9]{36,}",
    r"github_pat_[A-Za-z0-9_]{22,}",
    r"sk-[A-Za-z0-9_-]{20,}",
    r"xox[baprs]-[A-Za-z0-9-]{10,}",
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----",
    r"(?i)(?:password|token|secret|api_key)[=:]\S{8,}",
]

TOOLS = [
    {
        "name": "journal_get",
        "description": "OrgOS Central Activity Ledger の日次ダイジェストを取得する。"
                       "date (YYYY-MM-DD, 省略時は今日) と days (直近N日) を指定可能。"
                       "format は md (Markdown ダイジェスト) または json。",
        "inputSchema": {
            "type": "object",
            "properties": {
                "date": {"type": "string", "description": "YYYY-MM-DD (default: today)"},
                "days": {"type": "integer", "description": "lookback days ending at date (default: 1)"},
                "format": {"type": "string", "enum": ["md", "json"], "description": "output format (default: md)"},
            },
        },
    },
    {
        "name": "activity_search",
        "description": "全リポジトリ横断でアクティビティイベントを検索する。"
                       "query (title/detail/task_id の部分一致)、repo (リポジトリ名)、"
                       "type (event_type)、days (直近N日、default 30) で絞り込み。結果は JSON。",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "substring match on title/detail/task_id"},
                "repo": {"type": "string", "description": "repo name filter"},
                "type": {"type": "string", "description": "event_type filter"},
                "days": {"type": "integer", "description": "lookback days (default: 30)"},
            },
        },
    },
    {
        "name": "activity_log",
        "description": "Central Activity Ledger にイベントを記録する（どのリポジトリ・"
                       "プロジェクトからでも可）。type は note/thought/decision/task_done 等。",
        "inputSchema": {
            "type": "object",
            "properties": {
                "type": {"type": "string", "enum": list(EVENT_TYPES), "description": "event type"},
                "title": {"type": "string", "description": "one-line summary"},
                "detail": {"type": "string", "description": "optional detail"},
                "task_id": {"type": "string", "description": "optional task id (T-XXX)"},
            },
            "required": ["type", "title"],
        },
    },
]


# ---------------------------------------------------------------- store utils

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


def oneline(s):
    """Collapse newlines/tabs/whitespace so untrusted event fields cannot
    inject extra lines into the Markdown digest."""
    return " ".join(str(s or "").split())


ERRORS_LOG_MAX_BYTES = 5 * 1024 * 1024
ERROR_MSG_MAX_CHARS = 2000


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
            f.write("%s mcp-journal-server: %s\n"
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


def load_events(start, end, repo=None, ev_type=None):
    """Load events whose LOCAL date is within [start, end]."""
    months = set()
    d = start - datetime.timedelta(days=1)
    stop = end + datetime.timedelta(days=1)
    while d <= stop:
        months.add(d.strftime("%Y%m"))
        d += datetime.timedelta(days=1)

    events = []
    for month in sorted(months):
        path = os.path.join(STORE, "events-%s.jsonl" % month)
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
                    ev = json.loads(line)
                except Exception:
                    continue
                if not isinstance(ev, dict):
                    continue
                dt = parse_ts(str(ev.get("ts", "")))
                if dt is None:
                    continue
                local = dt.astimezone()
                if not (start <= local.date() <= end):
                    continue
                repo_name = ""
                if isinstance(ev.get("repo"), dict):
                    repo_name = str(ev["repo"].get("name", "") or "")
                if repo and repo_name != repo:
                    continue
                if ev_type and str(ev.get("event_type", "")) != ev_type:
                    continue
                events.append((dt, local, repo_name, ev))
    events.sort(key=lambda t: (t[0], str(t[3].get("event_id", ""))))
    return events


def render_digest_md(events, start, end):
    out = []
    if start == end:
        out.append("# OrgOS Journal — %s" % end.isoformat())
    else:
        out.append("# OrgOS Journal — %s 〜 %s" % (start.isoformat(), end.isoformat()))
    out.append("")
    if not events:
        out.append("(イベントなし)")
        return "\n".join(out)

    repos = []
    for _, _, repo_name, _ in events:
        if repo_name not in repos:
            repos.append(repo_name)
    sessions = sum(1 for e in events
                   if str(e[3].get("event_type", "")) == "session_start")
    out.append("## サマリ: %d リポジトリ / %d イベント / セッション %d 回"
               % (len(repos), len(events), sessions))
    out.append("")
    out.append("## 💭 考えたこと (decision/note/thought)")
    out.append("")
    thoughts = [e for e in events if str(e[3].get("event_type", "")) in THOUGHT_TYPES]
    if thoughts:
        for dt, local, repo_name, ev in thoughts:
            out.append("- %s [%s] %s" % (local.strftime("%H:%M"), oneline(repo_name),
                                         oneline(ev.get("title", ""))))
    else:
        out.append("(イベントなし)")
    out.append("")
    out.append("## ⚙️ 実行したこと")
    actions = [e for e in events if str(e[3].get("event_type", "")) not in THOUGHT_TYPES]
    if not actions:
        out.append("")
        out.append("(イベントなし)")
        return "\n".join(out)
    for repo_name in repos:
        group = [e for e in actions if e[2] == repo_name]
        if not group:
            continue
        out.append("")
        out.append("### %s" % (oneline(repo_name) or "(no repo)"))
        out.append("")
        for dt, local, rn, ev in group:
            task_id = oneline(ev.get("task_id", ""))
            suffix = " (%s)" % task_id if task_id else ""
            out.append("- %s %s %s%s" % (local.strftime("%H:%M"),
                                         oneline(ev.get("event_type", "")),
                                         oneline(ev.get("title", "")), suffix))
    return "\n".join(out)


def append_event(ev_type, title, detail="", task_id=""):
    if ev_type not in EVENT_TYPES:
        raise ValueError("invalid type %r (allowed: %s)"
                         % (ev_type, " ".join(EVENT_TYPES)))
    if not title:
        raise ValueError("title is required")

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
        "session_id": "",
        "actor": {"role": "manager", "id": "mcp-journal"},
        "event_type": ev_type,
        "task_id": task_id or "",
        "title": clean_text(title, 500),
        "detail": clean_text(detail or "", 2000, single_line=False),
        "source": "cli",
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

    # Upsert repos.json (atomic replace, best-effort).
    try:
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
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
            json.dump(repos, f, sort_keys=True, ensure_ascii=False, indent=2)
        os.replace(tmp_path, repos_path)
    except Exception as e:
        log_error("repos.json upsert failed: %s" % e)
    return event


# ---------------------------------------------------------------- tool calls

def parse_date_range(args, default_days=1):
    end = datetime.date.today()
    date_arg = args.get("date")
    if date_arg:
        try:
            end = datetime.datetime.strptime(str(date_arg), "%Y-%m-%d").date()
        except ValueError:
            raise ValueError("invalid date %r (expected YYYY-MM-DD)" % date_arg)
    days = default_days
    if args.get("days") is not None:
        try:
            days = int(args["days"])
        except (TypeError, ValueError):
            raise ValueError("invalid days %r" % args.get("days"))
        if days < 1:
            raise ValueError("days must be >= 1")
    start = end - datetime.timedelta(days=days - 1)
    return start, end


def tool_journal_get(args):
    start, end = parse_date_range(args, default_days=1)
    fmt = str(args.get("format") or "md")
    if fmt not in ("md", "json"):
        raise ValueError("invalid format %r (md|json)" % fmt)
    events = load_events(start, end)
    if fmt == "json":
        repos = []
        for _, _, repo_name, _ in events:
            if repo_name not in repos:
                repos.append(repo_name)
        sessions = sum(1 for e in events
                       if str(e[3].get("event_type", "")) == "session_start")
        payload = {
            "summary": {"repos": len(repos), "events": len(events),
                        "sessions": sessions},
            "events": [e[3] for e in events],
        }
        return json.dumps(payload, ensure_ascii=False, indent=2)
    return render_digest_md(events, start, end)


def tool_activity_search(args):
    days = 30
    if args.get("days") is not None:
        try:
            days = int(args["days"])
        except (TypeError, ValueError):
            raise ValueError("invalid days %r" % args.get("days"))
        if days < 1:
            raise ValueError("days must be >= 1")
    end = datetime.date.today()
    start = end - datetime.timedelta(days=days - 1)
    repo = str(args["repo"]) if args.get("repo") else None
    ev_type = str(args["type"]) if args.get("type") else None
    query = str(args.get("query") or "").lower()

    events = load_events(start, end, repo=repo, ev_type=ev_type)
    matched = []
    for dt, local, repo_name, ev in events:
        if query:
            haystack = " ".join([
                str(ev.get("title", "")), str(ev.get("detail", "")),
                str(ev.get("task_id", "")),
            ]).lower()
            if query not in haystack:
                continue
        matched.append(ev)
    return json.dumps({"count": len(matched), "events": matched},
                      ensure_ascii=False, indent=2)


def tool_activity_log(args):
    event = append_event(
        str(args.get("type") or ""),
        str(args.get("title") or ""),
        detail=str(args.get("detail") or ""),
        task_id=str(args.get("task_id") or ""),
    )
    return json.dumps({"logged": True, "event_id": event["event_id"],
                       "ts": event["ts"]}, ensure_ascii=False)


TOOL_HANDLERS = {
    "journal_get": tool_journal_get,
    "activity_search": tool_activity_search,
    "activity_log": tool_activity_log,
}


# ---------------------------------------------------------------- JSON-RPC

def rpc_result(req_id, result):
    return {"jsonrpc": "2.0", "id": req_id, "result": result}


def rpc_error(req_id, code, message):
    return {"jsonrpc": "2.0", "id": req_id,
            "error": {"code": code, "message": message}}


def handle_message(msg):
    """Return a response dict, or None for notifications."""
    if not isinstance(msg, dict):
        return rpc_error(None, -32600, "Invalid Request")
    method = msg.get("method")
    req_id = msg.get("id")
    is_notification = "id" not in msg

    if method == "initialize":
        params = msg.get("params") or {}
        client_pv = params.get("protocolVersion") or PROTOCOL_VERSION
        return rpc_result(req_id, {
            "protocolVersion": client_pv,
            "capabilities": {"tools": {}},
            "serverInfo": SERVER_INFO,
        })
    if method in ("notifications/initialized", "initialized"):
        return None
    if method == "ping":
        return None if is_notification else rpc_result(req_id, {})
    if method == "tools/list":
        return rpc_result(req_id, {"tools": TOOLS})
    if method == "tools/call":
        params = msg.get("params") or {}
        name = params.get("name")
        args = params.get("arguments") or {}
        if not isinstance(args, dict):
            return rpc_error(req_id, -32602, "arguments must be an object")
        handler = TOOL_HANDLERS.get(name)
        if handler is None:
            return rpc_error(req_id, -32602, "Unknown tool: %r" % name)
        try:
            text = handler(args)
            return rpc_result(req_id, {
                "content": [{"type": "text", "text": text}],
                "isError": False,
            })
        except ValueError as e:
            return rpc_result(req_id, {
                "content": [{"type": "text", "text": "error: %s" % e}],
                "isError": True,
            })
        except Exception as e:
            # exception type + sanitized message only (tool args are
            # caller-controlled; log_error also redacts/truncates)
            log_error("tools/call %s failed: %s: %s"
                      % (name, type(e).__name__, e))
            return rpc_result(req_id, {
                "content": [{"type": "text", "text": "internal error: %s" % e}],
                "isError": True,
            })
    if is_notification:
        return None
    return rpc_error(req_id, -32601, "Method not found: %r" % method)


def main():
    for raw in sys.stdin:
        raw = raw.strip()
        if not raw:
            continue
        try:
            msg = json.loads(raw)
        except Exception:
            resp = rpc_error(None, -32700, "Parse error")
            sys.stdout.write(json.dumps(resp, ensure_ascii=False) + "\n")
            sys.stdout.flush()
            continue
        try:
            resp = handle_message(msg)
        except Exception as e:
            log_error("handler crashed: %s" % e)
            resp = rpc_error(msg.get("id") if isinstance(msg, dict) else None,
                             -32603, "Internal error")
        if resp is not None:
            sys.stdout.write(json.dumps(resp, ensure_ascii=False) + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    main()
