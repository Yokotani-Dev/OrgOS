#!/usr/bin/env bash
# migrate-layout.sh — converge a repo from the OLD .ai layout to the NEW
# .ai/_machine layout. Idempotent: safe to run any number of times; a no-op
# when the repo is already migrated.
#
# Design: .ai/DESIGN/LAYOUT_MIGRATION_COMPAT.md §3 機構1, §5
#         .ai/DESIGN/ORGOS_TOBE_V3.md §4.3 (old -> new dir map)
#
# Behavior per (OLD, NEW) pair:
#   - OLD exists, NEW missing  -> move OLD to NEW (git mv when tracked, else mv)
#   - BOTH exist (partial/merge) -> move OLD's contents INTO NEW, never overwrite;
#                                   on collision keep both (suffix _from_legacy);
#                                   then remove the now-empty OLD
#   - only NEW exists or neither -> skip (already migrated / nothing to do)
#
# macOS bash 3.2 compatible. python3 (stdlib only) used for the events
# hash-chain verification.
#
# Exit 0 on success (warnings do not fail). Non-zero only on a real
# filesystem error.

set -u

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------
REPO_ROOT=""
DRY_RUN=0
QUIET=0

usage() {
  cat <<'EOF'
Usage: migrate-layout.sh [--repo-root PATH] [--dry-run] [--quiet]

  --repo-root PATH   Repo to migrate (default: git toplevel, else current dir)
  --dry-run          Print planned moves, change nothing
  --quiet            Suppress per-move logging (summary still printed)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --repo-root)
      REPO_ROOT="${2:-}"
      if [ -z "$REPO_ROOT" ]; then
        echo "migrate-layout: --repo-root requires a PATH" >&2
        exit 2
      fi
      shift 2
      ;;
    --repo-root=*)
      REPO_ROOT="${1#--repo-root=}"
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --quiet)
      QUIET=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "migrate-layout: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Resolve repo root
# ---------------------------------------------------------------------------
if [ -z "$REPO_ROOT" ]; then
  if REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then
    :
  else
    REPO_ROOT="$(pwd)"
  fi
fi

if [ ! -d "$REPO_ROOT" ]; then
  echo "migrate-layout: repo root does not exist: $REPO_ROOT" >&2
  exit 1
fi

# Normalize to an absolute path (bash 3.2: no realpath dependency).
REPO_ROOT=$(cd "$REPO_ROOT" 2>/dev/null && pwd)
if [ -z "$REPO_ROOT" ]; then
  echo "migrate-layout: cannot resolve repo root" >&2
  exit 1
fi

AI_DIR="$REPO_ROOT/.ai"
MACHINE_DIR="$AI_DIR/_machine"

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log() {
  if [ "$QUIET" -eq 0 ]; then
    printf '%s\n' "$*"
  fi
}

# Always-printed lines (summary / warnings) ignore --quiet for warnings only.
warn() {
  printf '%s\n' "$*"
}

# ---------------------------------------------------------------------------
# Migration map (OLD relative name -> NEW relative name under _machine)
# Source of truth: ORGOS_TOBE_V3.md §4.3
#
# bash 3.2 has no associative arrays; use a parallel-indexed pipe-delimited
# list. LEARNED+LEARNINGS both fold into learnings; ARTIFACTS+artifacts both
# fold into artifacts (handled by listing each OLD separately -> same NEW).
# ---------------------------------------------------------------------------
MAP="
SUPERVISOR_REVIEW|supervisor-review
LEARNED|learnings
LEARNINGS|learnings
APPROVALS|approvals
OS|os
BACKUPS|backups
INTEGRITY|integrity
SCHEDULER|scheduler
sessions|sessions
events|events
METRICS|metrics
leases|leases
REVIEW|review
ARTIFACTS|artifacts
artifacts|artifacts
queue|queue
INTELLIGENCE|intelligence
EVOLUTION|evolution
CODEX|codex
"

# ---------------------------------------------------------------------------
# git detection
# ---------------------------------------------------------------------------
INSIDE_GIT=0
if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  INSIDE_GIT=1
fi

# is_tracked PATH -> 0 if the path is tracked by git, 1 otherwise.
is_tracked() {
  local path="$1"
  [ "$INSIDE_GIT" -eq 1 ] || return 1
  git -C "$REPO_ROOT" ls-files --error-unmatch "$path" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------
MOVED=0
CURRENT=0
ERRORS=0
EVENTS_MOVED=0

# ---------------------------------------------------------------------------
# Move helpers
# ---------------------------------------------------------------------------

# git_mv_or_mv SRC DST — move SRC to DST, using `git mv` when SRC is tracked
# and we are inside a git work tree, else plain `mv`. Respects --dry-run.
git_mv_or_mv() {
  local src="$1"
  local dst="$2"
  local how="mv"
  if is_tracked "$src"; then
    how="git mv"
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log "  [dry-run] $how $src -> $dst"
    return 0
  fi

  if [ "$how" = "git mv" ]; then
    # git mv keeps history; -k would skip on error, but we want to know.
    if git -C "$REPO_ROOT" mv "$src" "$dst" 2>/dev/null; then
      log "  git mv $src -> $dst"
      return 0
    fi
    # Fall back to plain mv if git mv refuses (e.g. dst parent edge cases).
    if mv "$src" "$dst" 2>/dev/null; then
      log "  mv (git fallback) $src -> $dst"
      return 0
    fi
    return 1
  fi

  if mv "$src" "$dst" 2>/dev/null; then
    log "  mv $src -> $dst"
    return 0
  fi
  return 1
}

# ensure_parent DIR — mkdir -p the parent of DIR (the _machine dir). dry-run safe.
ensure_machine_dir() {
  if [ -d "$MACHINE_DIR" ]; then
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    log "  [dry-run] mkdir -p $MACHINE_DIR"
    return 0
  fi
  mkdir -p "$MACHINE_DIR" 2>/dev/null
}

# is_events_ledger NAME -> 0 if NAME matches the recognized events ledger glob
# (events-*.jsonl). The chain verifier and the activity bridge both glob
# `events-*.jsonl`; a salvage name that escapes this glob makes the legacy
# events invisible to replay even though the data is preserved on disk
# (T-OS-498 Risk 1).
is_events_ledger() {
  case "$1" in
    events-*.jsonl) return 0 ;;
    *) return 1 ;;
  esac
}

# merge_events_ledger LEGACY NEW_FILE — for a same-month events-*.jsonl
# collision, append every legacy line whose event_id is not already present in
# NEW_FILE, preserving the legacy order. Events keep their original hashes; the
# bridge/verifier key on event_id and tolerate the appended lines (re-linking is
# not required). A genuine content conflict (same event_id, different line) is
# salvaged to a name that STILL matches the events-*.jsonl glob so replay can
# see it, and is counted so the run surfaces it. Echoes "OK", "CONFLICT", or
# "ERROR". The legacy file is consumed (removed) on OK / CONFLICT.
merge_events_ledger() {
  local legacy="$1"
  local newf="$2"
  # Conflict salvage path: <newf-without-.jsonl>-legacy-conflict.jsonl, which
  # still ends in .jsonl and starts with events- so it matches events-*.jsonl.
  local conflict_path="${newf%.jsonl}-legacy-conflict.jsonl"

  LEGACY_FILE="$legacy" NEW_FILE="$newf" CONFLICT_FILE="$conflict_path" \
    python3 - <<'PY'
import json, os, sys

legacy = os.environ["LEGACY_FILE"]
newf = os.environ["NEW_FILE"]
conflict = os.environ["CONFLICT_FILE"]


def load(path):
    rows = []
    try:
        with open(path, "r", encoding="utf-8") as fh:
            for raw in fh:
                line = raw.rstrip("\n")
                if not line.strip():
                    continue
                eid = None
                try:
                    eid = json.loads(line).get("event_id")
                except Exception:
                    eid = None
                rows.append((eid, line))
    except FileNotFoundError:
        pass
    return rows


new_rows = load(newf)
legacy_rows = load(legacy)

# Map event_id -> exact line already present in the new file.
present = {}
for eid, line in new_rows:
    if eid is not None:
        present.setdefault(eid, line)

append_lines = []   # legacy lines to append (missing event_ids), order preserved
conflict_lines = []  # same event_id but different content
for eid, line in legacy_rows:
    if eid is None:
        # No event_id to dedup on: treat as a content conflict to avoid silent
        # duplication / loss; salvage it where replay can still see it.
        conflict_lines.append(line)
        continue
    if eid in present:
        if present[eid] != line:
            conflict_lines.append(line)
        # identical line already present -> nothing to do
    else:
        append_lines.append(line)
        present[eid] = line

status = "OK"
try:
    if append_lines:
        with open(newf, "a", encoding="utf-8") as fh:
            for line in append_lines:
                fh.write(line + "\n")
    if conflict_lines:
        status = "CONFLICT"
        with open(conflict, "a", encoding="utf-8") as fh:
            for line in conflict_lines:
                fh.write(line + "\n")
except OSError as exc:
    sys.stderr.write("merge_events_ledger: %s\n" % exc)
    print("ERROR")
    sys.exit(0)

print(status)
PY
}

# merge_into OLD NEW — move every entry of OLD into NEW. Never overwrite; on a
# name collision keep both by suffixing the legacy entry with _from_legacy.
# Exception (T-OS-498 Risk 1): a same-month events-*.jsonl collision is merged
# line-by-line into the existing new file so the legacy events stay visible to
# the events-*.jsonl glob. Then remove the now-empty OLD. Returns 0 on success,
# 1 on filesystem error.
merge_into() {
  local old="$1"
  local new="$2"
  local entry base name dest

  # Iterate visible + hidden entries (bash 3.2: use find -mindepth/-maxdepth).
  # -mindepth 1 -maxdepth 1 lists immediate children including dotfiles,
  # excluding '.' and '..'.
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    base=$(basename "$entry")
    dest="$new/$base"

    if [ -e "$dest" ]; then
      # T-OS-498 Risk 1: same-month events ledger collision. Suffixing with
      # _from_legacy escapes the events-*.jsonl glob and hides the legacy
      # events from replay. Instead, merge the legacy lines (by event_id,
      # order-preserving) into the existing new file. Conflicts are salvaged to
      # a still-matching name and counted.
      if is_events_ledger "$base" && [ -f "$entry" ] && [ -f "$dest" ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
          log "  [dry-run] merge events ledger $entry -> $dest (by event_id)"
          continue
        fi
        local er
        er=$(merge_events_ledger "$entry" "$dest")
        case "$er" in
          OK)
            log "  merge events ledger $entry -> $dest (legacy lines appended)"
            ;;
          CONFLICT)
            warn "migrate-layout: events ledger conflict merging $base; legacy-conflict lines salvaged to ${dest%.jsonl}-legacy-conflict.jsonl (still matches events-*.jsonl)"
            ERRORS=$((ERRORS + 1))
            ;;
          *)
            warn "migrate-layout: ERROR merging events ledger $entry -> $dest"
            return 1
            ;;
        esac
        # Consume the legacy file (its content is now folded into the new file
        # and/or the salvage file).
        if is_tracked "$entry"; then
          git -C "$REPO_ROOT" rm -q -f "$entry" 2>/dev/null || rm -f "$entry" 2>/dev/null || true
        else
          rm -f "$entry" 2>/dev/null || true
        fi
        continue
      fi

      # Collision: keep both. Suffix the legacy copy.
      name="${base}_from_legacy"
      dest="$new/$name"
      # If the suffixed name also exists, append a numeric discriminator.
      local n=1
      while [ -e "$dest" ]; do
        dest="$new/${base}_from_legacy_${n}"
        n=$((n + 1))
      done
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
      log "  [dry-run] merge $entry -> $dest"
      continue
    fi

    if is_tracked "$entry"; then
      if ! git -C "$REPO_ROOT" mv "$entry" "$dest" 2>/dev/null; then
        if ! mv "$entry" "$dest" 2>/dev/null; then
          warn "migrate-layout: ERROR merging $entry -> $dest"
          return 1
        fi
      fi
    else
      if ! mv "$entry" "$dest" 2>/dev/null; then
        warn "migrate-layout: ERROR merging $entry -> $dest"
        return 1
      fi
    fi
    log "  merge $entry -> $dest"
  done <<EOF
$(find "$old" -mindepth 1 -maxdepth 1 2>/dev/null)
EOF

  # Remove the now-empty OLD directory.
  if [ "$DRY_RUN" -eq 1 ]; then
    log "  [dry-run] rmdir $old (after merge)"
    return 0
  fi
  # rmdir only succeeds when empty; if leftovers remain it is a real error.
  if [ -d "$old" ]; then
    rmdir "$old" 2>/dev/null || {
      # Could still contain files if merge was partial. Surface as error.
      if [ -n "$(find "$old" -mindepth 1 -maxdepth 1 2>/dev/null)" ]; then
        warn "migrate-layout: ERROR could not empty legacy dir $old"
        return 1
      fi
      # Empty but rmdir failed for another reason; try once more.
      rmdir "$old" 2>/dev/null || true
    }
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Case-only collision handling (APFS case-insensitive filesystems)
#
# ARTIFACTS -> artifacts and artifacts -> artifacts can collide when the
# filesystem is case-insensitive: `.ai/ARTIFACTS` and `.ai/_machine/artifacts`
# are different paths (different parent), so the normal merge logic is safe.
# The genuine hazard is a *case-only rename in the same parent*, which never
# happens here because every NEW path lives under _machine/. We still guard the
# ARTIFACTS move with a two-step temp rename so that, on a case-insensitive FS
# where `.ai/_machine/ARTIFACTS` and `.ai/_machine/artifacts` would be aliases,
# the move cannot silently merge into the wrong-cased target.
# ---------------------------------------------------------------------------
case_safe_move() {
  # case_safe_move SRC DST — used when SRC and DST basenames differ only by
  # case under what could be the same directory on a case-insensitive FS.
  local src="$1"
  local dst="$2"
  local tmp="${dst}.migrate_tmp_$$"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "  [dry-run] case-safe move $src -> $tmp -> $dst"
    return 0
  fi

  # Step 1: move SRC to a temp name that cannot alias DST.
  if is_tracked "$src"; then
    git -C "$REPO_ROOT" mv "$src" "$tmp" 2>/dev/null || mv "$src" "$tmp" 2>/dev/null || return 1
  else
    mv "$src" "$tmp" 2>/dev/null || return 1
  fi
  # Step 2: move temp into the final (correct-case) DST.
  if is_tracked "$tmp"; then
    git -C "$REPO_ROOT" mv "$tmp" "$dst" 2>/dev/null || mv "$tmp" "$dst" 2>/dev/null || return 1
  else
    mv "$tmp" "$dst" 2>/dev/null || return 1
  fi
  log "  case-safe move $src -> $dst"
  return 0
}

# is_case_collision_pair OLD_NAME NEW_NAME -> 0 when this is the ARTIFACTS ->
# artifacts mapping. ARTIFACTS and artifacts are two distinct OLD names that
# both fold to the single NEW target `artifacts`; on a case-insensitive
# filesystem `.ai/ARTIFACTS` and `.ai/artifacts` alias the same directory, and a
# direct `git mv` of the upper-cased source can create a wrong-cased target.
# Every other §4.3 rename (OS->os, EVOLUTION->evolution, ...) moves between
# different parent directories with a unique target, so a plain move is safe
# there even on a case-insensitive FS. Restricting the two-step to ARTIFACTS
# keeps the rest on the cleaner single `git mv`/`mv` path.
is_case_collision_pair() {
  local old_name="$1"
  local new_name="$2"
  [ "$old_name" = "ARTIFACTS" ] && [ "$new_name" = "artifacts" ]
}

# is_case_insensitive_fs DIR -> 0 if filesystem under DIR is case-insensitive.
is_case_insensitive_fs() {
  local dir="$1"
  local probe="$dir/.case_probe_$$"
  [ -d "$dir" ] || return 1
  : > "${probe}_a" 2>/dev/null || return 1
  # If the uppercased name resolves to the same inode, FS is case-insensitive.
  local rc=1
  if [ -e "${probe}_A" ]; then
    rc=0
  fi
  rm -f "${probe}_a" "${probe}_A" 2>/dev/null
  return $rc
}

# ---------------------------------------------------------------------------
# Process one (OLD, NEW) pair.
# ---------------------------------------------------------------------------
process_pair() {
  local old_name="$1"
  local new_name="$2"
  local old="$AI_DIR/$old_name"
  local new="$MACHINE_DIR/$new_name"

  # Skip if OLD does not exist (already migrated or nothing to do).
  if [ ! -e "$old" ]; then
    # Count as already-current only when the NEW target exists.
    if [ -e "$new" ]; then
      CURRENT=$((CURRENT + 1))
    fi
    return 0
  fi

  # If OLD is actually the same path as NEW (can happen on case-insensitive FS
  # where ARTIFACTS aliases artifacts under the SAME parent — not our case since
  # parents differ), skip defensively.
  if [ "$old" = "$new" ]; then
    CURRENT=$((CURRENT + 1))
    return 0
  fi

  ensure_machine_dir || {
    warn "migrate-layout: ERROR cannot create $MACHINE_DIR"
    ERRORS=$((ERRORS + 1))
    return 1
  }

  if [ ! -e "$new" ]; then
    # Simple move. Use the case-safe two-step ONLY for the genuine APFS hazard:
    # the ARTIFACTS/artifacts pair, where two OLD names (differing only by case)
    # both map to the same NEW target. On a case-insensitive filesystem a direct
    # `git mv` of the upper-cased source could create a wrong-cased target that
    # aliases the lower-cased one; the temp-rename two-step avoids that.
    log "migrate-layout: $old_name -> _machine/$new_name (move)"
    if is_case_collision_pair "$old_name" "$new_name" && \
       is_case_insensitive_fs "$MACHINE_DIR"; then
      if case_safe_move "$old" "$new"; then
        MOVED=$((MOVED + 1))
        return 0
      fi
      warn "migrate-layout: ERROR case-safe move $old -> $new"
      ERRORS=$((ERRORS + 1))
      return 1
    fi
    if git_mv_or_mv "$old" "$new"; then
      MOVED=$((MOVED + 1))
      [ "$new_name" = "events" ] && EVENTS_MOVED=1
      return 0
    fi
    warn "migrate-layout: ERROR moving $old -> $new"
    ERRORS=$((ERRORS + 1))
    return 1
  fi

  # BOTH exist: merge OLD's contents into NEW.
  log "migrate-layout: $old_name -> _machine/$new_name (merge)"
  if merge_into "$old" "$new"; then
    MOVED=$((MOVED + 1))
    [ "$new_name" = "events" ] && EVENTS_MOVED=1
    return 0
  fi
  warn "migrate-layout: ERROR merging $old -> $new"
  ERRORS=$((ERRORS + 1))
  return 1
}

# ---------------------------------------------------------------------------
# Events hash-chain verification (post-move). Verifies prev_hash linkage only
# (the design's requirement: each line's prev_hash == previous line's hash).
# Never fails the script — prints OK / WARN.
# ---------------------------------------------------------------------------
verify_events_chain() {
  local events_dir="$MACHINE_DIR/events"
  [ -d "$events_dir" ] || return 0

  local f
  for f in "$events_dir"/events-*.jsonl; do
    [ -e "$f" ] || continue
    local result
    result=$(EVENTS_FILE="$f" python3 - <<'PY'
import json, os, sys

path = os.environ["EVENTS_FILE"]
prev = None
line_no = 0
try:
    with open(path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line_no += 1
            line = raw.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except Exception:
                print(f"WARN parse error at line {line_no}")
                sys.exit(0)
            ph = ev.get("prev_hash")
            h = ev.get("hash")
            if not isinstance(h, str):
                print(f"WARN missing hash at line {line_no}")
                sys.exit(0)
            if prev is not None and ph != prev:
                print(f"WARN broken chain at line {line_no}: prev_hash != previous hash")
                sys.exit(0)
            prev = h
    print("OK")
except FileNotFoundError:
    print("OK")
PY
)
    if [ "$result" = "OK" ]; then
      log "migrate-layout: events chain $(basename "$f") OK"
    else
      warn "migrate-layout: events chain $(basename "$f") $result"
    fi
  done
  return 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  if [ ! -d "$AI_DIR" ]; then
    # No .ai dir at all: nothing to migrate. Report a clean summary.
    log "migrate-layout: no .ai directory at $REPO_ROOT — nothing to do"
    printf 'migrate-layout: moved 0 dir(s), 0 already-current, 0 errors\n'
    return 0
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log "migrate-layout: DRY RUN (no changes will be made) — repo: $REPO_ROOT"
  else
    log "migrate-layout: repo: $REPO_ROOT"
  fi

  # Process each pair in map order.
  local line old_name new_name
  while IFS='|' read -r old_name new_name; do
    [ -n "$old_name" ] || continue
    process_pair "$old_name" "$new_name"
  done <<EOF
$(printf '%s\n' "$MAP" | grep '|')
EOF

  # Post-move events chain verification (skip on dry-run; nothing moved).
  if [ "$DRY_RUN" -eq 0 ] && [ "$EVENTS_MOVED" -eq 1 ]; then
    verify_events_chain
  fi

  printf 'migrate-layout: moved %d dir(s), %d already-current, %d errors\n' \
    "$MOVED" "$CURRENT" "$ERRORS"

  if [ "$ERRORS" -gt 0 ]; then
    return 1
  fi
  return 0
}

main
exit $?
