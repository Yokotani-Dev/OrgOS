#!/usr/bin/env bash
# PlanContractRequired invariant tests.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

PYTHONPATH="$REPO_ROOT/.claude/hooks${PYTHONPATH:+:$PYTHONPATH}" python3 <<'PY'
import tempfile
from pathlib import Path

import policy_core


def enforce(invariants=None):
    return {"default": "enforce", "invariants": invariants or {}}


def warn(invariants=None):
    return {"default": "warn", "invariants": invariants or {}}


def lease(task_id, *paths):
    return {"status": "active", "task_id": task_id, "allowed_paths": list(paths)}


def make_repo():
    tmp = tempfile.TemporaryDirectory()
    root = Path(tmp.name)
    (root / ".ai" / "plans").mkdir(parents=True)
    return tmp, root


def write_plan(root, task_id):
    (root / ".ai" / "plans" / f"{task_id}.plan.yaml").write_text(
        f"task_id: {task_id}\n",
        encoding="utf-8",
    )


def assert_equal(actual, expected, name):
    if actual != expected:
        raise AssertionError(f"{name}: expected {expected!r}, got {actual!r}")


def test_edit_without_plan_denied_in_enforce_mode():
    tmp, root = make_repo()
    with tmp:
        decision = policy_core.evaluate(
            "Edit",
            "",
            "src/app.py",
            str(root),
            "codex",
            [lease("T-NO-PLAN", "src/")],
            enforce(),
        )
    assert_equal(decision.outcome, "deny", "missing plan edit outcome")
    assert_equal(decision.invariant_id, "PlanContractRequired", "missing plan edit invariant")
    assert_equal(
        decision.reason,
        "PlanContractRequired: .ai/plans/T-NO-PLAN.plan.yaml not found",
        "missing plan edit reason",
    )


def test_write_without_plan_denied_in_enforce_mode():
    tmp, root = make_repo()
    with tmp:
        decision = policy_core.evaluate(
            "Write",
            "",
            "src/generated.py",
            str(root),
            "codex",
            [lease("T-WRITE-NO-PLAN", "src/")],
            enforce(),
        )
    assert_equal(decision.outcome, "deny", "missing plan write outcome")
    assert_equal(decision.invariant_id, "PlanContractRequired", "missing plan write invariant")


def test_edit_with_valid_plan_allowed():
    tmp, root = make_repo()
    with tmp:
        write_plan(root, "T-WITH-PLAN")
        decision = policy_core.evaluate(
            "Edit",
            "",
            "src/app.py",
            str(root),
            "codex",
            [lease("T-WITH-PLAN", "src/")],
            enforce(),
        )
    assert_equal(decision.outcome, "allow", "valid plan edit outcome")


def test_edit_on_plan_contract_path_allowed_for_bootstrap():
    tmp, root = make_repo()
    with tmp:
        decision = policy_core.evaluate(
            "Edit",
            "",
            ".ai/plans/T-BOOTSTRAP.plan.yaml",
            str(root),
            "codex",
            [lease("T-BOOTSTRAP", ".ai/plans/")],
            enforce(),
        )
    assert_equal(decision.outcome, "allow", "plan contract path bootstrap outcome")


def test_warn_mode_allows_with_warning():
    tmp, root = make_repo()
    with tmp:
        decision = policy_core.evaluate(
            "Edit",
            "",
            "src/app.py",
            str(root),
            "codex",
            [lease("T-WARN-NO-PLAN", "src/")],
            warn(),
        )
    assert_equal(decision.outcome, "warn", "warn mode outcome")
    assert_equal(decision.invariant_id, "PlanContractRequired", "warn mode invariant")


def test_disabled_mode_allows_silently():
    tmp, root = make_repo()
    with tmp:
        decision = policy_core.evaluate(
            "Edit",
            "",
            "src/app.py",
            str(root),
            "codex",
            [lease("T-DISABLED-NO-PLAN", "src/")],
            enforce({"PlanContractRequired": "disabled"}),
        )
    assert_equal(decision.outcome, "allow", "disabled mode outcome")


def test_covering_lease_resolves_task_id():
    tmp, root = make_repo()
    with tmp:
        write_plan(root, "T-COVERED")
        active_leases = [
            lease("T-MISSING", "docs/"),
            lease("T-COVERED", "src/"),
        ]
        decision = policy_core.evaluate(
            "Edit",
            "",
            "src/app.py",
            str(root),
            "codex",
            active_leases,
            enforce(),
        )
        assert_equal(decision.outcome, "allow", "covered lease plan outcome")

        decision = policy_core.evaluate(
            "Edit",
            "",
            "docs/readme.md",
            str(root),
            "codex",
            active_leases,
            enforce(),
        )
    assert_equal(decision.outcome, "deny", "missing covered lease plan outcome")
    assert_equal(decision.invariant_id, "PlanContractRequired", "missing covered lease plan invariant")


def test_git_commit_checks_current_task_plan():
    tmp, root = make_repo()
    with tmp:
        decision = policy_core.evaluate(
            "Bash",
            "git commit -m test",
            "",
            str(root),
            "codex",
            [lease("T-COMMIT-NO-PLAN", "src/")],
            enforce({"IntegratorOnlyCommit": "disabled"}),
        )
    assert_equal(decision.outcome, "deny", "git commit missing plan outcome")
    assert_equal(decision.invariant_id, "PlanContractRequired", "git commit missing plan invariant")


tests = [
    test_edit_without_plan_denied_in_enforce_mode,
    test_write_without_plan_denied_in_enforce_mode,
    test_edit_with_valid_plan_allowed,
    test_edit_on_plan_contract_path_allowed_for_bootstrap,
    test_warn_mode_allows_with_warning,
    test_disabled_mode_allows_silently,
    test_covering_lease_resolves_task_id,
    test_git_commit_checks_current_task_plan,
]

for test in tests:
    test()
    print(f"ok - {test.__name__}")

print(f"PlanContractRequired tests: {len(tests)} passed, 0 failed")
PY
