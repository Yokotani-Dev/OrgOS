#!/usr/bin/env bash
# Regression: shadow stage must NOT consult or mutate the circuit breaker (it changes
# no files). A stale/open breaker must never red the observation-only scheduler CI run.
# Root cause fixed in T-OS-503 (apply.sh gated breaker check + increment-apply to non-shadow).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

CB="$REPO_ROOT/.ai/_machine/evolution/circuit-breaker.yaml"
BACKUP="$(mktemp)"
TMP="$(mktemp -d)"
restore() {
  if [ -f "$BACKUP" ]; then cp "$BACKUP" "$CB" 2>/dev/null || true; fi
  bash scripts/evolution/circuit-breaker.sh restore >/dev/null 2>&1 || true
  rm -rf "$TMP" "$BACKUP" 2>/dev/null || true
}
trap restore EXIT

pass=0; fail=0
check() { if eval "$2"; then echo "ok - $1"; pass=$((pass + 1)); else echo "not ok - $1"; fail=$((fail + 1)); fi; }

# Preserve real breaker state, then trip it open.
[ -f "$CB" ] && cp "$CB" "$BACKUP"
bash scripts/evolution/circuit-breaker.sh trip "regression test: shadow must ignore breaker" >/dev/null 2>&1

PROP="$(ls -t "$REPO_ROOT"/.ai/_machine/evolution/proposals/*.yaml 2>/dev/null | head -1)"
if [ -z "$PROP" ]; then
  echo "ok - no proposal fixture available (skip)"; echo "scheduler-shadow tests: 1 passed, 0 failed"; exit 0
fi

mkdir -p "$TMP/proposals" "$TMP/applied"
cp "$PROP" "$TMP/proposals/"
PNAME="$(basename "$PROP")"

out="$(PROPOSAL_DIR="$TMP/proposals" APPLIED_DIR="$TMP/applied" \
  bash scripts/evolution/apply.sh "$TMP/proposals/$PNAME" --stage shadow 2>&1)"
rc=$?

check "shadow apply succeeds while breaker is OPEN" "[ $rc -eq 0 ]"
check "shadow recorded the candidate" "grep -q shadow_recorded <<<\"\$out\""
check "shadow did not hit the circuit breaker" "! grep -qi circuit_breaker_open <<<\"\$out\""
check "breaker remains open after shadow (untouched)" "grep -qiE 'breaker_state:[[:space:]]*\"?open' \"$CB\""

echo "scheduler-shadow tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
