# Memory Safety Scripts

## `check-no-plain-secrets.sh`

Pre-commit scanner for plain secret candidates in staged files and Codex output.

Usage:

```sh
bash scripts/memory/check-no-plain-secrets.sh [file ...]
```

Behavior:

- With file arguments, only those files are scanned.
- With no arguments, staged files from `git diff --cached --name-only --diff-filter=ACMRT` are scanned.
- `*.example.*`, `*.template.*`, and `tests/fixtures/*` are skipped.
- `1password://...`, `op://...`, `env://...`, `keychain://...`, and `sops://...` pointers are allowed because they are references, not secret material.
- If `gitleaks` is installed, it is run in addition to the built-in pattern scanner. Set `SECRET_SCAN_GITLEAKS=0` to disable that local optional pass.

Built-in detections:

- OpenAI / Anthropic-style `sk-` tokens
- Anthropic `sk-ant-` tokens
- GitHub `ghp_` and `gho_` tokens
- Slack `xox...` tokens
- AWS `AKIA...` access keys
- PEM private key headers
- JWT-like three-segment tokens

Exit codes:

- `0`: clean
- `1`: secret candidate found; commit should be blocked
- `2`: scanner execution error

False-positive allowlist:

- Prefer moving examples into `*.example.*`, `*.template.*`, or `tests/fixtures/*`.
- For a single line that must remain in a scanned file, add `secret-scan: allow` or `gitleaks:allow` on that same line.
- Do not allowlist real credentials. Replace real values with a pointer such as `op://vault/item/field`.
