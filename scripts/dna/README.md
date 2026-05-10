# OrgOS DNA Scripts

`scripts/dna/regenerate.sh` maintains `.ai/ORG_DNA.yaml`, the self-description registry for OrgOS rules, agents, skills, capabilities, schemas, and commands.

## Commands

```sh
scripts/dna/regenerate.sh
scripts/dna/regenerate.sh --dry-run
scripts/dna/regenerate.sh --bump-version patch
scripts/dna/diff.sh 0.1.0 0.1.1
```

## Behavior

- Scans `.claude/rules`, `.claude/agents`, `.claude/skills`, `.claude/schemas`, `.claude/commands`, and `.ai/CAPABILITIES.example.yaml`.
- Uses `.orgos-manifest.yaml` only as a read-only classification seed.
- Defaults components to `managed`; manifest `preserve` paths are `owner-edited`; generated DNA infrastructure is `generated`.
- Writes structured JSON logs to stderr.
- Appends previous-version snapshots to `.ai/DNA_HISTORY.yaml` before updates.
- Keeps `.orgos-manifest.yaml` read-only for T-OS-323. Manifest export switching is deferred to the follow-up task.

## Safety

DNA must not contain secrets. The scanner is intentionally limited to OS definition directories and `.ai/CAPABILITIES.example.yaml`; it does not read `.env`, `.env.*`, or `secrets/**`.
