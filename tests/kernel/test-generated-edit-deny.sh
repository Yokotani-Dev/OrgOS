#!/usr/bin/env bash
# Generated-file direct edit denial tests.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

PYTHONPATH="$REPO_ROOT/.claude/hooks${PYTHONPATH:+:$PYTHONPATH}" python3 <<'PY'
import policy_core


def enforce(invariants=None):
    return {"default": "enforce", "invariants": invariants or {}}


def active_lease(*paths):
    return [{"status": "active", "allowed_paths": list(paths)}]


def assert_equal(actual, expected, name):
    if actual != expected:
        raise AssertionError(f"{name}: expected {expected!r}, got {actual!r}")


def assert_true(value, name):
    if not value:
        raise AssertionError(f"{name}: expected truthy value")


def test_generated_suffix_pattern_matches():
    assert_true(policy_core.is_generated_file(".ai/TASKS.generated.yaml"), "TASKS.generated.yaml detected")
    assert_true(policy_core.is_generated_file("reports/summary.generated.json"), "summary.generated.json detected")


def test_edit_generated_file_denied():
    decision = policy_core.evaluate(
        "Edit",
        "",
        ".ai/DASHBOARD.generated.md",
        "/repo",
        "codex",
        active_lease(".ai/"),
        enforce(),
    )
    assert_equal(decision.outcome, "deny", "generated edit outcome")
    assert_equal(decision.invariant_id, "StateMutationViaOrgTool", "generated edit invariant")
    assert_equal(decision.reason, "direct edit of generated file blocked", "generated edit reason")


def test_write_generated_file_denied():
    decision = policy_core.evaluate(
        "Write",
        "",
        "docs/reference.generated.md",
        "/repo",
        "codex",
        active_lease("docs/"),
        enforce(),
    )
    assert_equal(decision.outcome, "deny", "generated write outcome")
    assert_equal(decision.invariant_id, "StateMutationViaOrgTool", "generated write invariant")
    assert_equal(decision.reason, "direct edit of generated file blocked", "generated write reason")


def test_non_generated_leased_write_allowed():
    decision = policy_core.evaluate(
        "Write",
        "",
        "docs/reference.md",
        "/repo",
        "codex",
        active_lease("docs/"),
        enforce(),
    )
    assert_equal(decision.outcome, "allow", "non-generated leased write outcome")


tests = [
    test_generated_suffix_pattern_matches,
    test_edit_generated_file_denied,
    test_write_generated_file_denied,
    test_non_generated_leased_write_allowed,
]

for test in tests:
    test()
    print(f"ok - {test.__name__}")

print(f"generated edit deny tests: {len(tests)} passed, 0 failed")
PY
