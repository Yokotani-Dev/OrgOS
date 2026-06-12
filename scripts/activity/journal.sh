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
    actions = [e for e in events if str(e[3].get("event_type", "")) not in THOUGHT_TYPES]
    if not actions:
        print()
        print("(イベントなし)")
        return
    for repo_name in repos:
        group = [e for e in actions if e[2] == repo_name]
        if not group:
            continue
        print()
        print("### %s" % (oneline(repo_name) or "(no repo)"))
        print()
        for dt, local, rn, ev in group:
            task_id = oneline(ev.get("task_id", ""))
            suffix = " (%s)" % task_id if task_id else ""
            print("- %s %s %s%s" % (local.strftime("%H:%M"),
                                    oneline(ev.get("event_type", "")),
                                    oneline(ev.get("title", "")), suffix))


main()
PYEOF
