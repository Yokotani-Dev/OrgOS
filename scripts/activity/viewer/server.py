#!/usr/bin/env python3
"""OrgOS Activity Ledger — local read-only viewer server.

Self-contained: standard library only (http.server, json, urllib, datetime,
pathlib, os, glob, re, webbrowser). No third-party deps. Binds to 127.0.0.1
only. Read-only: no endpoint writes or deletes events.

Store dir resolution: env ORGOS_ACTIVITY_DIR, else ~/.orgos/activity
Event files: <store>/events-YYYYMM.jsonl (one JSON object per line).
Times are stored in UTC ISO8601 and displayed in local time by the browser.

Run:
    python3 server.py [--port 7777] [--no-browser]
"""

import argparse
import glob
import json
import os
import re
import sys
import webbrowser
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

HOST = "127.0.0.1"
DEFAULT_PORT = 7777
SCHEMA_VERSION = "orgos-activity.v1"

DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
SHARD_RE = re.compile(r"events-(\d{6})\.jsonl$")

# Events that represent "考えたこと" (thoughts). Everything else is an action.
THOUGHT_TYPES = {"decision", "note", "thought"}


def store_dir() -> Path:
    """Resolve the activity store directory."""
    env = os.environ.get("ORGOS_ACTIVITY_DIR")
    if env:
        return Path(env).expanduser()
    return Path.home() / ".orgos" / "activity"


def _shard_months_for_range(start_utc: datetime, end_utc: datetime):
    """Yield YYYYMM strings for every month touched by [start_utc, end_utc]."""
    months = []
    y, m = start_utc.year, start_utc.month
    while (y, m) <= (end_utc.year, end_utc.month):
        months.append("%04d%02d" % (y, m))
        m += 1
        if m > 12:
            m = 1
            y += 1
    return months


def _parse_event(line: str):
    """Parse one JSONL line into an event dict, or None if invalid/garbage."""
    line = line.strip()
    if not line:
        return None
    try:
        obj = json.loads(line)
    except (ValueError, TypeError):
        return None
    if not isinstance(obj, dict):
        return None
    ts = obj.get("ts")
    if not isinstance(ts, str) or not ts:
        return None
    return obj


def _parse_ts(ts: str):
    """Parse a UTC ISO8601 timestamp into an aware datetime, or None."""
    if not isinstance(ts, str):
        return None
    s = ts.strip()
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(s)
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def load_events(start_utc: datetime, end_utc: datetime):
    """Load events whose ts is within [start_utc, end_utc] from shard files.

    Reads only the monthly shards covering the requested range. Tolerates a
    missing store dir and garbage lines (skipped silently).
    """
    base = store_dir()
    events = []
    if not base.is_dir():
        return events
    for ym in _shard_months_for_range(start_utc, end_utc):
        shard = base / ("events-%s.jsonl" % ym)
        if not shard.is_file():
            continue
        try:
            with shard.open("r", encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    obj = _parse_event(line)
                    if obj is None:
                        continue
                    dt = _parse_ts(obj.get("ts"))
                    if dt is None:
                        continue
                    if start_utc <= dt <= end_utc:
                        events.append(obj)
        except OSError:
            continue
    events.sort(key=lambda e: e.get("ts", ""))
    return events


def _repo_name(ev) -> str:
    repo = ev.get("repo")
    if isinstance(repo, dict):
        n = repo.get("name")
        if isinstance(n, str) and n:
            return n
    return "unknown"


def estimate_active_hours(events):
    """Rough estimate of active hours from session_start -> session_end pairs.

    Pairs are matched per (repo, session_id). Falls back to None when no
    completed pairs can be derived.
    """
    starts = {}
    total = 0.0
    matched = 0
    for ev in events:
        et = ev.get("event_type")
        if et not in ("session_start", "session_end"):
            continue
        key = (_repo_name(ev), ev.get("session_id") or "")
        dt = _parse_ts(ev.get("ts"))
        if dt is None:
            continue
        if et == "session_start":
            starts[key] = dt
        elif et == "session_end":
            start_dt = starts.pop(key, None)
            if start_dt is not None and dt >= start_dt:
                delta = (dt - start_dt).total_seconds()
                # ignore implausibly long pairs (> 24h) to keep estimate sane
                if 0 <= delta <= 24 * 3600:
                    total += delta
                    matched += 1
    if matched == 0:
        return None
    return round(total / 3600.0, 1)


def build_summary(events):
    repos = set()
    sessions = set()
    for ev in events:
        repos.add(_repo_name(ev))
        sid = ev.get("session_id")
        if isinstance(sid, str) and sid:
            sessions.add(sid)
    return {
        "repos": len(repos),
        "events": len(events),
        "sessions": len(sessions),
        "active_hours": estimate_active_hours(events),
    }


def filter_events(events, repo=None, etype=None, q=None):
    out = events
    if repo:
        out = [e for e in out if _repo_name(e) == repo]
    if etype:
        out = [e for e in out if e.get("event_type") == etype]
    if q:
        ql = q.lower()

        def hit(e):
            for field in ("title", "detail", "task_id", "branch"):
                v = e.get(field)
                if isinstance(v, str) and ql in v.lower():
                    return True
            actor = e.get("actor")
            if isinstance(actor, dict):
                aid = actor.get("id")
                if isinstance(aid, str) and ql in aid.lower():
                    return True
            return False

        out = [e for e in out if hit(e)]
    return out


def resolve_range(params):
    """Return (start_utc, end_utc, error_message).

    Priority: explicit date= (single local day) > days=N (last N local days
    ending today) > default today (local).
    """
    local_tz = datetime.now().astimezone().tzinfo

    def day_bounds(local_day_start):
        end = local_day_start + timedelta(days=1) - timedelta(microseconds=1)
        return (
            local_day_start.astimezone(timezone.utc),
            end.astimezone(timezone.utc),
        )

    date_param = params.get("date", [None])[0]
    days_param = params.get("days", [None])[0]

    if date_param is not None:
        if not DATE_RE.match(date_param):
            return None, None, "invalid date format (expected YYYY-MM-DD)"
        try:
            d = datetime.strptime(date_param, "%Y-%m-%d")
        except ValueError:
            return None, None, "invalid date value"
        start_local = d.replace(tzinfo=local_tz)
        s, e = day_bounds(start_local)
        return s, e, None

    if days_param is not None:
        try:
            n = int(days_param)
        except (ValueError, TypeError):
            return None, None, "invalid days value"
        if n < 1 or n > 366:
            return None, None, "days out of range (1-366)"
        today_local = datetime.now(local_tz).replace(
            hour=0, minute=0, second=0, microsecond=0
        )
        start_local = today_local - timedelta(days=n - 1)
        end_local = today_local + timedelta(days=1) - timedelta(microseconds=1)
        return (
            start_local.astimezone(timezone.utc),
            end_local.astimezone(timezone.utc),
            None,
        )

    # default: today (local)
    today_local = datetime.now(local_tz).replace(
        hour=0, minute=0, second=0, microsecond=0
    )
    s, e = day_bounds(today_local)
    return s, e, None


def list_repos():
    """Return [{name, remote, event_count}] for filter chips.

    Counts come from scanning recent shards; remotes are enriched from
    repos.json when present.
    """
    base = store_dir()
    counts = {}
    remotes = {}

    # event counts from shard files
    if base.is_dir():
        for shard in glob.glob(str(base / "events-*.jsonl")):
            try:
                with open(shard, "r", encoding="utf-8", errors="replace") as fh:
                    for line in fh:
                        obj = _parse_event(line)
                        if obj is None:
                            continue
                        name = _repo_name(obj)
                        counts[name] = counts.get(name, 0) + 1
                        repo = obj.get("repo")
                        if isinstance(repo, dict):
                            rem = repo.get("remote")
                            if isinstance(rem, str) and rem and name not in remotes:
                                remotes[name] = rem
            except OSError:
                continue

    # enrich/augment with repos.json
    repos_json = base / "repos.json"
    if repos_json.is_file():
        try:
            data = json.loads(repos_json.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                for name, meta in data.items():
                    if not isinstance(name, str):
                        continue
                    counts.setdefault(name, 0)
                    if isinstance(meta, dict):
                        rem = meta.get("remote")
                        if isinstance(rem, str) and rem:
                            remotes.setdefault(name, rem)
        except (OSError, ValueError):
            pass

    out = [
        {"name": name, "remote": remotes.get(name, ""), "event_count": cnt}
        for name, cnt in counts.items()
    ]
    out.sort(key=lambda r: (-r["event_count"], r["name"]))
    return out


class Handler(BaseHTTPRequestHandler):
    server_version = "OrgOSActivityViewer/1.0"

    def log_message(self, fmt, *args):  # quieter logging
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def _send_json(self, obj, status=200):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _send_error_json(self, status, message):
        self._send_json({"error": message}, status=status)

    def _send_html(self, path: Path):
        try:
            body = path.read_bytes()
        except OSError:
            self._send_error_json(500, "index.html not found")
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlparse(self.path)
        route = parsed.path
        params = parse_qs(parsed.query)

        if route == "/" or route == "/index.html":
            self._send_html(Path(__file__).resolve().parent / "index.html")
            return

        if route == "/api/events":
            self._handle_events(params)
            return

        if route == "/api/repos":
            self._send_json({"repos": list_repos()})
            return

        if route == "/api/health":
            self._send_json({"ok": True, "store": str(store_dir())})
            return

        self._send_error_json(404, "not found")

    def _handle_events(self, params):
        start_utc, end_utc, err = resolve_range(params)
        if err:
            self._send_error_json(400, err)
            return

        repo = (params.get("repo", [None])[0] or None)
        etype = (params.get("type", [None])[0] or None)
        q = (params.get("q", [None])[0] or None)

        try:
            all_events = load_events(start_utc, end_utc)
        except Exception:  # never crash on bad data
            all_events = []

        events = filter_events(all_events, repo=repo, etype=etype, q=q)
        summary = build_summary(events)
        self._send_json({"summary": summary, "events": events})

    # Read-only viewer: explicitly reject mutating methods.
    def do_POST(self):
        self._send_error_json(405, "read-only viewer")

    def do_PUT(self):
        self._send_error_json(405, "read-only viewer")

    def do_DELETE(self):
        self._send_error_json(405, "read-only viewer")


def serve(port, open_browser):
    last_err = None
    for candidate in range(port, port + 10):
        try:
            httpd = ThreadingHTTPServer((HOST, candidate), Handler)
        except OSError as exc:
            last_err = exc
            continue
        url = "http://%s:%d/" % (HOST, candidate)
        print("OrgOS Activity Viewer")
        print("  store: %s" % store_dir())
        print("  serving: %s" % url)
        if candidate != port:
            print("  (port %d was busy; bound %d instead)" % (port, candidate))
        if open_browser:
            try:
                webbrowser.open(url)
            except Exception:
                pass
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nstopped.")
        finally:
            httpd.server_close()
        return 0
    print("error: could not bind any port in range %d-%d (%s)"
          % (port, port + 9, last_err), file=sys.stderr)
    return 1


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="OrgOS Activity Ledger local viewer (read-only)."
    )
    parser.add_argument("--port", type=int, default=DEFAULT_PORT,
                        help="port to bind (default %d)" % DEFAULT_PORT)
    parser.add_argument("--no-browser", action="store_true",
                        help="do not open the default browser on start")
    args = parser.parse_args(argv)
    return serve(args.port, open_browser=not args.no_browser)


if __name__ == "__main__":
    sys.exit(main())
