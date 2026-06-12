#!/usr/bin/env bash
# tests/activity/test-concurrent-append.sh — parallel append integrity.
# Spec: .ai/DESIGN/ACTIVITY_LEDGER.md §3 / §7 (7): concurrent appends from
# multiple processes must not corrupt lines.
# bash 3.2 compatible. Never touches the real ~/.orgos.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
LOG="$REPO_ROOT/scripts/activity/log-event.sh"

STORE=$(mktemp -d)
trap 'rm -rf "$STORE"' EXIT
export ORGOS_ACTIVITY_DIR="$STORE"

N=20  # events per writer

writer() {
  # writer <label>
  i=1
  while [ "$i" -le "$N" ]; do
    bash "$LOG" --type note --title "writer-$1 event $i" --source cli </dev/null
    i=$((i + 1))
  done
}

writer A &
pid_a=$!
writer B &
pid_b=$!
wait "$pid_a" "$pid_b"

shard="$STORE/events-$(date -u +%Y%m).jsonl"
if [ ! -f "$shard" ]; then
  echo "FAIL: shard not created"; exit 1
fi

total=$(wc -l < "$shard" | tr -d ' ')
expected=$((N * 2))
if [ "$total" -ne "$expected" ]; then
  echo "FAIL: expected $expected lines, got $total"
  exit 1
fi

# Every line must be intact JSON with the expected schema + both writers present.
if ! python3 - "$shard" "$N" <<'PY'
import json, sys
path, n = sys.argv[1], int(sys.argv[2])
a = b = 0
for i, line in enumerate(open(path, encoding="utf-8"), 1):
    line = line.rstrip("\n")
    assert line, "empty line %d" % i
    ev = json.loads(line)  # raises on corruption
    assert ev["schema_version"] == "orgos-activity.v1", "line %d schema" % i
    if ev["title"].startswith("writer-A"):
        a += 1
    elif ev["title"].startswith("writer-B"):
        b += 1
assert a == n, "writer-A wrote %d/%d" % (a, n)
assert b == n, "writer-B wrote %d/%d" % (b, n)
PY
then
  echo "FAIL: corrupted or missing lines after concurrent append"
  exit 1
fi

echo "test-concurrent-append: all assertions passed ($expected intact lines)"
