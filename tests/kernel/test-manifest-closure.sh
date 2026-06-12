#!/usr/bin/env bash
# Manifest dependency closure invariants (ISS-006 / ISS-007, AUDIT-2026-06-10).
# A repo that runs /org-import must receive a WORKING OrgOS:
# every distributed file's dependencies must also be distributed.
#
# Checks:
# (a) every path in .orgos-manifest.yaml publish + core exists on disk
# (b) every hook command registered in .claude/settings.json references a
#     file that is either in the publish list or explicitly whitelisted below
# (c) closure spot-checks for the key references fixed on 2026-06-11
#     (hooks, scripts/session, scripts/platform, scripts/capabilities,
#      scripts/memory, scripts/org, schemas, manager.md, kernel-write-path)
# (d) core is a subset of publish (anything /org-import copies must be
#     present in the public repo)
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
MANIFEST="$REPO_ROOT/.orgos-manifest.yaml"
SETTINGS="$REPO_ROOT/.claude/settings.json"

# Hook-referenced files that are intentionally NOT distributed.
# Each entry needs a reason. Currently empty: every registered hook and the
# scripts they invoke are part of the publish set (ISS-007 / ISS-008 fix).
HOOK_WHITELIST=(
)

pass_count=0
fail_count=0
current_test_failed=0

fail() {
  printf 'not ok - %s\n' "$1" >&2
  current_test_failed=1
}

run_test() {
  local name="$1"
  current_test_failed=0
  "$name"
  if [ "$current_test_failed" -eq 0 ]; then
    printf 'ok - %s\n' "$name"
    pass_count=$((pass_count + 1))
  else
    fail_count=$((fail_count + 1))
  fi
}

# --- manifest parsing helpers (line-based; PyYAML is not stdlib) ---------

manifest_section() {
  # Print entries of a top-level list section ("publish" or "core").
  local section="$1"
  awk -v section="$section" '
    /^[a-z_]+:/ {
      in_section = ($0 ~ "^" section ":")
      next
    }
    in_section && match($0, /^[[:space:]]+-[[:space:]]+"[^"]+"/) {
      line = $0
      sub(/^[[:space:]]+-[[:space:]]+"/, "", line)
      sub(/".*$/, "", line)
      print line
    }
  ' "$MANIFEST"
}

test_manifest_exists() {
  [ -f "$MANIFEST" ] || fail "manifest missing: $MANIFEST"
  [ -f "$SETTINGS" ] || fail "settings.json missing: $SETTINGS"
}

# (a) every path in publish + core exists on disk
test_publish_and_core_paths_exist() {
  local section path count
  for section in publish core; do
    count=0
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      count=$((count + 1))
      [ -e "$REPO_ROOT/$path" ] || fail "$section lists missing file: $path"
    done <<EOF
$(manifest_section "$section")
EOF
    [ "$count" -gt 0 ] || fail "manifest section '$section' parsed as empty"
  done
}

# (d) core must be a subset of publish
test_core_subset_of_publish() {
  local missing
  missing=$(
    {
      manifest_section core
      manifest_section publish
      manifest_section publish
    } | sort | uniq -u
  )
  if [ -n "$missing" ]; then
    fail "core entries not present in publish: $(printf '%s ' $missing)"
  fi
}

# (b) every hook command in settings.json maps to a distributed file
test_settings_hooks_are_distributed() {
  local result
  result=$(python3 - "$SETTINGS" "$MANIFEST" "${HOOK_WHITELIST[@]:-}" <<'PY'
import json
import re
import sys

settings_path, manifest_path = sys.argv[1], sys.argv[2]
whitelist = {w for w in sys.argv[3:] if w}

# publish list (line-based parse; PyYAML is not stdlib)
publish = set()
section = None
with open(manifest_path) as f:
    for line in f:
        m = re.match(r"^([a-z_]+):", line)
        if m:
            section = m.group(1)
            continue
        m = re.match(r'^\s+-\s+"([^"]+)"', line)
        if m and section == "publish":
            publish.add(m.group(1))

with open(settings_path) as f:
    settings = json.load(f)

commands = []
for event, groups in (settings.get("hooks") or {}).items():
    for group in groups:
        for hook in group.get("hooks", []):
            cmd = hook.get("command", "")
            if cmd:
                commands.append((event, cmd))

if not commands:
    print("FAIL no hook commands found in settings.json")
    sys.exit(0)

path_pattern = re.compile(
    r'(?:"\$CLAUDE_PROJECT_DIR"/)?'
    r"((?:\.claude/hooks|scripts/[a-z]+)/[A-Za-z0-9_\-./]+)"
)

errors = []
for event, cmd in commands:
    refs = path_pattern.findall(cmd)
    if not refs:
        errors.append(f"{event}: no recognizable file reference in: {cmd}")
        continue
    for ref in refs:
        if ref in whitelist:
            continue
        if ref not in publish:
            errors.append(f"{event}: hook file not in publish: {ref} (cmd: {cmd})")

if errors:
    for e in errors:
        print(f"FAIL {e}")
else:
    print(f"OK {len(commands)} hook commands all map to published files")
PY
  )
  if printf '%s\n' "$result" | grep -q '^FAIL'; then
    printf '%s\n' "$result" | grep '^FAIL' | while IFS= read -r line; do
      printf 'not ok - settings hook: %s\n' "${line#FAIL }" >&2
    done
    current_test_failed=1
  fi
}

# (c) closure spot-checks for key references fixed in this change
test_closure_spot_checks() {
  local publish ref
  publish=$(manifest_section publish)

  # referencing file (must be distributed) -> referenced file (must be distributed)
  # Format: "<referenced path>|<why>"
  local checks=(
    ".claude/hooks/pretool_policy.py|settings.json PreToolUse hook"
    ".claude/hooks/policy_core.py|imported by pretool_policy.py"
    ".claude/hooks/session_start_context.py|settings.json SessionStart hook"
    ".claude/hooks/stop_gate.py|settings.json Stop hook"
    ".claude/hooks/session_memory.py|settings.json Stop hook"
    ".claude/hooks/SessionStart.sh|settings.json SessionStart hook (ISS-008)"
    "scripts/org/check-generated-checksums.py|invoked by SessionStart.sh"
    "scripts/session/bootstrap.sh|settings.json SessionStart + session-bootstrap.md"
    "scripts/session/common.sh|sourced by scripts/session/*.sh"
    "scripts/session/load-ledger.sh|sourced by suggest-next.sh"
    "scripts/session/bind-request.sh|cross-session-consistency.md Iron Law"
    "scripts/session/suggest-next.sh|proactive-mode.md Iron Law"
    "scripts/session/priority-ranker.sh|invoked by suggest-next.sh"
    "scripts/platform/detect.sh|org-import.md / org-start.md / agent-coordination.md"
    "scripts/capabilities/scan.sh|capability-preflight.md Iron Law"
    "scripts/capabilities/probe/cli-generic.sh|invoked by scan.sh"
    "scripts/memory/check-no-plain-secrets.sh|memory-lifecycle.md lint"
    "scripts/security/common.sh|sourced by scripts/memory/*.sh"
    "scripts/org/update-task.py|kernel-write-path.md / org-tick.md / CLAUDE.md"
    "scripts/org/append-decision.py|kernel-write-path.md / org-tick.md / CLAUDE.md"
    "scripts/org/append-event.py|kernel-write-path.md / collect-artifacts.sh"
    "scripts/org/generate-dashboard.py|kernel-write-path.md"
    "scripts/org/integrator-commit.sh|kernel-write-path.md"
    "scripts/org/secret-get.sh|secret-management.md + scan.sh"
    "scripts/org/secret-set.sh|secret-management.md"
    "scripts/org/archive-tasks.py|check-schema.sh"
    "scripts/org/import-tasks-yaml.py|check-schema.sh"
    "scripts/codex/run-in-worktree.sh|parallel-session-policy.md Iron Law"
    ".claude/agents/manager.md|CLAUDE.md / KERNEL_FILES (ISS-006)"
    ".claude/agents/CODEX_WORKER_GUIDE.md|AGENTS.md / handoff-protocol.md"
    ".claude/rules/kernel-write-path.md|CLAUDE.md / AGENTS.md / org-tick.md"
    ".claude/rules/request-intake-loop.md|CLAUDE.md top Iron Law"
    ".claude/rules/parallel-session-policy.md|KERNEL_FILES entry"
    ".claude/schemas/handoff-packet.yaml|handoff-protocol.md / agents"
    ".claude/schemas/plan-contract.v1.json|integrator-commit.sh"
    ".claude/evals/run-all.sh|org-tick / org-evolve eval gate"
    ".claude/evals/check-kernel-boundary.sh|run-all.sh unconditional call"
    ".claude/evals/check-schema.sh|run-all.sh unconditional call"
    ".claude/evals/check-agent-defs.sh|run-all.sh unconditional call"
    ".claude/evals/check-security.sh|run-all.sh unconditional call"
    ".claude/skills/karpathy-guidelines.md|AGENTS.md baseline doc"
    ".ai/TEMPLATES/THREAT_MODEL.md|design-documentation.md / specialist agents"
    ".ai/TEMPLATES/DATA_MODEL_FULL.md|design-documentation.md / specialist agents"
    ".ai/TEMPLATES/AUTHORITY_BOUNDARY.md|design-documentation.md / specialist agents"
    ".ai/TEMPLATES/DOMAIN_ANALYSIS.md|specialist-subagents.md"
    ".claude/settings.json|hook wiring must ship with the hooks (ISS-007)"
  )

  local entry why
  for entry in "${checks[@]}"; do
    ref="${entry%%|*}"
    why="${entry#*|}"
    if ! printf '%s\n' "$publish" | grep -Fxq "$ref"; then
      fail "publish missing dependency: $ref (needed by: $why)"
    fi
    [ -e "$REPO_ROOT/$ref" ] || fail "spot-check file missing on disk: $ref"
  done
}

# run-all.sh must not unconditionally call an eval script that is missing
# from publish (P2#3: set -e crash in distributed repos)
test_run_all_unconditional_evals_distributed() {
  local publish run_all script
  publish=$(manifest_section publish)
  run_all="$REPO_ROOT/.claude/evals/run-all.sh"
  [ -f "$run_all" ] || { fail "run-all.sh missing"; return 0; }

  # Unconditional calls: run_eval lines NOT wrapped in an if [[ -f ... ]] guard.
  # Heuristic matching the current file layout: guarded calls are indented.
  while IFS= read -r script; do
    [ -n "$script" ] || continue
    if ! printf '%s\n' "$publish" | grep -Fxq ".claude/evals/$script"; then
      fail "run-all.sh unconditionally calls .claude/evals/$script but it is not in publish"
    fi
  done <<EOF
$(grep -E '^run_eval ' "$run_all" | grep -oE '\$SCRIPT_DIR/[A-Za-z0-9_\-]+\.sh' | sed 's|\$SCRIPT_DIR/||')
EOF
}

run_test test_manifest_exists
run_test test_publish_and_core_paths_exist
run_test test_core_subset_of_publish
run_test test_settings_hooks_are_distributed
run_test test_closure_spot_checks
run_test test_run_all_unconditional_evals_distributed

printf 'manifest closure tests: %d passed, %d failed\n' "$pass_count" "$fail_count"
[ "$fail_count" -eq 0 ]
