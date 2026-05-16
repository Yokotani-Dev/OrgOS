# Secret Management Policy

> API keys, tokens, passwords, and other secrets must be stored outside the repository.

---

## Scope

This rule applies to all secrets used by OrgOS workers, scripts, tests, and operator workflows.

Secrets include:

- API keys
- access tokens and refresh tokens
- passwords and passphrases
- private keys
- database credentials
- webhook signing secrets
- session cookies

## Storage Policy

Secrets must not be written directly into these repository areas:

- `.ai/`
- `.claude/`
- `outputs/`
- `scripts/`

This includes source files, generated reports, logs, fixtures, markdown notes, shell history captures, and temporary debug output committed or stored under the repository.

Non-secret identifiers such as service names, account names, and placeholder values are allowed when they cannot authenticate to any system.

## Retrieval Policy

All secret reads must go through:

```bash
scripts/org/secret-get.sh <service> <account>
```

Workers and scripts must not call `security find-generic-password` directly unless they are maintaining the secret helper itself.

The helper prints only the secret value to stdout. Callers must avoid echoing, logging, or writing that value into repository files.

## Enforcement Direction

A pretool policy will deny writes when common secret patterns are detected in protected repository locations. The detection implementation is tracked separately, but the intended behavior is:

- detect likely API keys, tokens, passwords, private keys, and credential URLs
- deny writes into `.ai/`, `.claude/`, `outputs/`, and `scripts/`
- report the matched policy category without printing the secret value

## macOS Keychain

OrgOS uses macOS Keychain for local secret storage.

### Register Or Update A Secret

Use the helper:

```bash
printf '%s' '<secret-value>' | scripts/org/secret-set.sh <service> <account> --read-stdin
```

For interactive entry:

```bash
scripts/org/secret-set.sh <service> <account> --prompt
```

Equivalent Keychain operation:

```bash
security add-generic-password -s <service> -a <account> -w '<secret-value>' -U
```

### Read A Secret

```bash
scripts/org/secret-get.sh <service> <account>
```

Equivalent Keychain operation:

```bash
security find-generic-password -s <service> -a <account> -w
```

### Delete A Secret

```bash
security delete-generic-password -s <service> -a <account>
```

Deletion is intentionally not wrapped by the read helper. Operators should delete entries explicitly and verify the service/account pair before running the command.

## Operational Notes

- Use stable service names such as `orgos/openai` or `orgos/github`.
- Use account names that identify the owner or purpose, such as `default`, `owner`, or a machine-local account label.
- Do not place actual secret values in Work Orders, review packets, logs, or test fixtures.
- Tests must use mocks or temporary fake values that cannot authenticate to any real service.
