#!/usr/bin/env bash
# Pure policy_core unit tests.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

PYTHONPATH="$REPO_ROOT/.claude/hooks${PYTHONPATH:+:$PYTHONPATH}" python3 <<'PY'
import policy_core


def enforce(invariants=None):
    return {"default": "enforce", "invariants": invariants or {}}


def warn(invariants=None):
    return {"default": "warn", "invariants": invariants or {}}


def active_lease(*paths):
    return [{"status": "active", "allowed_paths": list(paths)}]


def assert_equal(actual, expected, name):
    if actual != expected:
        raise AssertionError(f"{name}: expected {expected!r}, got {actual!r}")


def assert_true(value, name):
    if not value:
        raise AssertionError(f"{name}: expected truthy value")


def test_evaluate_raw_git_commit_denied():
    decision = policy_core.evaluate("Bash", "git commit -m test", "", "/repo", "codex", [], enforce())
    assert_equal(decision.outcome, "deny", "raw git commit outcome")
    assert_equal(decision.invariant_id, "IntegratorOnlyCommit", "raw git commit invariant")


def test_evaluate_integrator_subprocess_allow():
    decision = policy_core.evaluate("Bash", "scripts/org/integrator-commit.sh --task-id T", "", "/repo", "integrator", [], enforce())
    assert_equal(decision.outcome, "allow", "integrator subprocess command")


def test_evaluate_protected_branch_checkout_denied():
    decision = policy_core.evaluate("Bash", "git checkout main", "", "/repo", "codex", [], enforce())
    assert_equal(decision.outcome, "deny", "protected branch checkout outcome")
    assert_equal(decision.invariant_id, "ProtectedBranchNoTouch", "protected branch checkout invariant")


def test_evaluate_lease_present_allows_write():
    decision = policy_core.evaluate("Edit", "", "src/auth/login.ts", "/repo", "codex", active_lease("src/auth/"), enforce())
    assert_equal(decision.outcome, "allow", "lease present write")


def test_evaluate_lease_absent_denies_write():
    decision = policy_core.evaluate("Edit", "", "src/auth/login.ts", "/repo", "codex", [], enforce())
    assert_equal(decision.outcome, "deny", "lease absent write outcome")
    assert_equal(decision.invariant_id, "LeaseBeforeWrite", "lease absent write invariant")


def test_parse_git_command_basic():
    git = policy_core.parse_git_command("git commit --no-verify -m test")
    assert_equal(git.subcmd, "commit", "basic git subcmd")
    assert_true("--no-verify" in git.args, "basic git args")


def test_parse_git_command_with_env_prefix():
    git = policy_core.parse_git_command("ORGOS_INTEGRATOR=1 git commit -m bypass")
    assert_equal(git.subcmd, "commit", "env prefix git subcmd")
    git = policy_core.parse_git_command('echo "ORGOS_INTEGRATOR=1"; git commit -m sneaky')
    assert_equal(git.subcmd, "commit", "compound git subcmd")


def test_path_covers_exact_match():
    assert_true(policy_core.path_covers("src/auth/login.ts", "src/auth/login.ts"), "exact path covers")


def test_path_covers_prefix():
    assert_true(policy_core.path_covers("src/auth/", "src/auth/login.ts"), "prefix path covers")


def test_path_covers_glob():
    assert_true(policy_core.path_covers("src/**/*.ts", "src/auth/login.ts"), "glob path covers")


def test_is_protected_state_file_events_jsonl():
    assert_true(policy_core.is_protected_state_file(".ai/EVENTS.jsonl"), "EVENTS protected")


def test_is_protected_state_file_tasks_yaml():
    assert_true(policy_core.is_protected_state_file("./.ai/TASKS.yaml"), "TASKS protected")


def test_per_invariant_mode_enforced_before_warn():
    decision = policy_core.evaluate(
        "Bash",
        "git commit -m x && rm -rf /tmp/orgos-krt-noop",
        "",
        "/repo",
        "codex",
        [],
        warn({"IntegratorOnlyCommit": "enforce", "DangerousShell": "warn"}),
    )
    assert_equal(decision.outcome, "deny", "per-invariant enforced outcome")
    assert_equal(decision.invariant_id, "IntegratorOnlyCommit", "per-invariant enforced invariant")


tests = [
    test_evaluate_raw_git_commit_denied,
    test_evaluate_integrator_subprocess_allow,
    test_evaluate_protected_branch_checkout_denied,
    test_evaluate_lease_present_allows_write,
    test_evaluate_lease_absent_denies_write,
    test_parse_git_command_basic,
    test_parse_git_command_with_env_prefix,
    test_path_covers_exact_match,
    test_path_covers_prefix,
    test_path_covers_glob,
    test_is_protected_state_file_events_jsonl,
    test_is_protected_state_file_tasks_yaml,
    test_per_invariant_mode_enforced_before_warn,
]

for test in tests:
    test()
    print(f"ok - {test.__name__}")

print(f"policy_core tests: {len(tests)} passed, 0 failed")
PY
