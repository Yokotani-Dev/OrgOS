#!/bin/bash
# scripts/activity/journal.sh — Central Activity Ledger query / digest
#
# Usage:
#   journal.sh today                     # today's digest (Markdown)
#   journal.sh --date 2026-06-10         # specific day
#   journal.sh --days 7                  # last 7 days (ending today, or --date)
#   journal.sh --repo OrgOS --type note  # filters
#   journal.sh --format md|json|tsv      # default: md
#
# Reads only the monthly shards covering the requested range.
# Store: $ORGOS_ACTIVITY_DIR or ~/.orgos/activity
# Self-contained: bash 3.2 + python3 stdlib only.

STORE="${ORGOS_ACTIVITY_DIR:-$HOME/.orgos/activity}"
export ORGOS_ACTIVITY_STORE="$STORE"

if ! command -v python3 >/dev/null 2>&1; then
  echo "journal.sh: python3 not found" >&2
  exit 1
fi

exec python3 - "$@" <<'PYEOF'
import datetime
import json
import os
import sys

STORE = os.environ.get("ORGOS_ACTIVITY_STORE") or os.path.expanduser("~/.orgos/activity")
THOUGHT_TYPES = ("decision", "note", "thought")

# Session boundary events. By default these dominate the ledger and bury the
# events that actually say "what was done", so we collapse the bare ones into a
# per-repo "セッション N 回" summary and only surface the *rich* session_end
# events (the ones summarize-session.sh emits, carrying commit/task info).
SESSION_BOUNDARY_TYPES = ("session_start", "session_end")

# Events that should appear first in "⚙️ 実行したこと" (most signal).
PRIORITY_ACTION_TYPES = ("commit", "task_done", "task_created", "decision",
                         "release")

# Bare session_end titles carry no useful "what happened" payload.
_BARE_SESSION_TITLES = ("session end", "session_end", "session start",
                        "session_start", "")


def is_rich_session_end(ev):
    """A session_end is 'rich' (worth showing individually) when it carries a
    summary: a non-bare title, a non-empty detail, or an attached task_id.
    Bare boundary events (title 'session end', empty detail) are collapsed."""
    if str(ev.get("event_type", "")) != "session_end":
        return False
    title = oneline(ev.get("title", "")).lower()
    detail = oneline(ev.get("detail", ""))
    task_id = oneline(ev.get("task_id", ""))
    if detail:
        return True
    if task_id:
        return True
    if title and title not in _BARE_SESSION_TITLES:
        return True
    return False


def action_sort_key(triple):
    """Sort actions so priority types (commit/task_done/...) come first, then
    rich session summaries, then everything else, each by time ascending.
    triple is (dt, local, repo_name, ev)."""
    ev = triple[3]
    et = str(ev.get("event_type", ""))
    if et in PRIORITY_ACTION_TYPES:
        rank = 0
    elif is_rich_session_end(ev):
        rank = 1
    else:
        rank = 2
    return (rank, triple[0], str(ev.get("event_id", "")))


def oneline(s):
    """Collapse newlines/tabs/whitespace runs so untrusted event fields
    cannot inject extra lines/columns into the md digest or tsv rows."""
    return " ".join(str(s or "").split())


def fail(msg):
    sys.stderr.write("journal.sh: %s\n" % msg)
    sys.exit(1)


def parse_args(argv):
    opts = {"date": None, "days": None, "repo": None, "type": None,
            "format": "md", "today": False}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "today":
            opts["today"] = True
            i += 1
            continue
        if a in ("--date", "--days", "--repo", "--type", "--format"):
            if i + 1 >= len(argv):
                fail("missing value for %s" % a)
            opts[a[2:]] = argv[i + 1]
            i += 2
            continue
        fail("unknown argument: %s" % a)
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


def main():
    opts = parse_args(sys.argv[1:])
    fmt = opts["format"]
    if fmt not in ("md", "json", "tsv"):
        fail("invalid --format %r (md|json|tsv)" % fmt)

    end = datetime.date.today()
    if opts["date"]:
        try:
            end = datetime.datetime.strptime(opts["date"], "%Y-%m-%d").date()
        except ValueError:
            fail("invalid --date %r (expected YYYY-MM-DD)" % opts["date"])
    days = 1
    if opts["days"] is not None:
        try:
            days = int(opts["days"])
        except ValueError:
            fail("invalid --days %r" % opts["days"])
        if days < 1:
            fail("--days must be >= 1")
    start = end - datetime.timedelta(days=days - 1)

    # Months (UTC shards) covering [start-1d, end+1d] for tz-boundary safety.
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
                if opts["repo"] and repo_name != opts["repo"]:
                    continue
                if opts["type"] and str(ev.get("event_type", "")) != opts["type"]:
                    continue
                events.append((dt, local, repo_name, ev))

    events.sort(key=lambda t: (t[0], str(t[3].get("event_id", ""))))

    if fmt == "json":
        print(json.dumps([e[3] for e in events], ensure_ascii=False, indent=2))
        return

    if fmt == "tsv":
        for dt, local, repo_name, ev in events:
            row = [oneline(ev.get("ts", "")), oneline(repo_name),
                   oneline(ev.get("event_type", "")), oneline(ev.get("task_id", "")),
                   oneline(ev.get("title", ""))]
            print("\t".join(row))
        return

    # Markdown digest
    if start == end:
        print("# OrgOS Journal — %s" % end.isoformat())
    else:
        print("# OrgOS Journal — %s 〜 %s" % (start.isoformat(), end.isoformat()))
    print()
    if not events:
        print("(イベントなし)")
        return

    repos = []
    for _, _, repo_name, _ in events:
        if repo_name not in repos:
            repos.append(repo_name)
    sessions = sum(1 for e in events
                   if str(e[3].get("event_type", "")) == "session_start")
    print("## サマリ: %d リポジトリ / %d イベント / セッション %d 回"
          % (len(repos), len(events), sessions))
    print()

    print("## 💭 考えたこと (decision/note/thought)")
    print()
    thoughts = [e for e in events if str(e[3].get("event_type", "")) in THOUGHT_TYPES]
    if thoughts:
        for dt, local, repo_name, ev in thoughts:
            print("- %s [%s] %s" % (local.strftime("%H:%M"), oneline(repo_name),
                                    oneline(ev.get("title", ""))))
    else:
        print("(イベントなし)")
    print()

    print("## ⚙️ 実行したこと")
    # Actions = non-thoughts. Split off bare session-boundary noise: it is
    # collapsed into a per-repo count line, while rich session_end summaries
    # and all other action events are listed normally.
    actions = []
    boundary_counts = {}  # repo_name -> count of bare boundary events
    for e in events:
        et = str(e[3].get("event_type", ""))
        if et in THOUGHT_TYPES:
            continue
        if et in SESSION_BOUNDARY_TYPES and not is_rich_session_end(e[3]):
            boundary_counts[e[2]] = boundary_counts.get(e[2], 0) + 1
            continue
        actions.append(e)

    if not actions and not boundary_counts:
        print()
        print("(イベントなし)")
        return

    for repo_name in repos:
        group = sorted([e for e in actions if e[2] == repo_name],
                       key=action_sort_key)
        bcount = boundary_counts.get(repo_name, 0)
        if not group and not bcount:
            continue
        print()
        print("### %s" % (oneline(repo_name) or "(no repo)"))
        print()
        # Collapsed session-boundary summary first (compact, secondary signal).
        if bcount:
            print("- _セッション %d 回_（境界イベントは折りたたみ）" % bcount)
        for dt, local, rn, ev in group:
            task_id = oneline(ev.get("task_id", ""))
            suffix = " (%s)" % task_id if task_id else ""
            print("- %s %s %s%s" % (local.strftime("%H:%M"),
                                    oneline(ev.get("event_type", "")),
                                    oneline(ev.get("title", "")), suffix))


main()
PYEOF
