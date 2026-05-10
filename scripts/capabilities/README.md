# Capability Probe and Role Routing

This directory contains offline-first capability tooling for T-OS-327.

## `probe-new.sh`

Detects new model-alias, MCP, and CLI capabilities by comparing known entries in
`.ai/CAPABILITIES.example.yaml` with an offline stub or a user-supplied fixture.
It does not call provider APIs and does not read secret-bearing environment
variables.

Default behavior writes proposal YAMLs to `.ai/EVOLUTION/proposals/` using the
T-OS-324 evolution proposal shape:

```bash
bash scripts/capabilities/probe-new.sh
```

Smoke and offline checks can avoid repo writes:

```bash
bash scripts/capabilities/probe-new.sh --dry-run --stdout
bash scripts/capabilities/probe-new.sh --source-fixture /tmp/new-capabilities.yaml --dry-run
```

Fixture shape:

```yaml
capabilities:
  - id: reasoning-primary@^1.1.0
    kind: model_alias
    source: openai_changelog_stub
    source_url: stub://openai/changelog
    role_hint: deep-reasoning
    capability_class: reasoning
    summary: New reasoning alias candidate.
    target_file: .claude/schemas/capability-roles.yaml
```

The script logs JSON lines to stderr. Missing or unreadable source fixtures are
treated as graceful skips.

## `role-routing.sh`

Returns a proposal-only routing recommendation for a role id. Recommendations
use semver-style aliases from `.claude/schemas/capability-roles.yaml`; provider
model names are intentionally not resolved here.

```bash
bash scripts/capabilities/role-routing.sh deep-reasoning
bash scripts/capabilities/role-routing.sh fast-classification --json
bash scripts/capabilities/role-routing.sh code-generation
```

Each result includes:

- recommended model alias
- reason based on required characteristics
- fallback chain
- regression test reference
- semantic equivalence test placeholder

Automatic model switching and automatic regression execution are out of scope.
