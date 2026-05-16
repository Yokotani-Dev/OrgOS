# Runbook: shellcheck

> Codex 実装の shell script 検証で shellcheck を使う。
> T-OS-382 (Pro feedback) で確立。

## Install

```bash
brew install shellcheck
```

## Usage in Codex Work Orders

Acceptance Criteria に追加:
```
- shellcheck で warning ゼロ (shellcheck script.sh)
```

Codex は `bash -n` (syntax check) + `shellcheck` を両方実行。
shellcheck 未インストール環境は明記する (例: "shellcheck not installed in this environment, could not run").

## CI 統合 (future)

```yaml
# .github/workflows/shellcheck.yml (例)
- run: brew install shellcheck
- run: find scripts -name '*.sh' -print0 | xargs -0 shellcheck
```

