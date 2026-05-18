#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: collect-artifacts.sh --task-id T-OS-XXX --run-id RUN_ID --worktree-path PATH --artifact-dir PATH --stdout-source PATH --stderr-source PATH --last-message-source PATH --actor-role ROLE --actor-id ID

Collect stdout/stderr, output-last-message, git status/diff, and untracked
files into an artifact directory, then write artifact_manifest.json and
artifact_manifest.sha256.
USAGE
}

task_id=""
run_id=""
worktree_path=""
artifact_dir=""
stdout_source=""
stderr_source=""
last_message_source=""
actor_role=""
actor_id=""

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
APPEND_EVENT=${ORGOS_APPEND_EVENT:-"$REPO_ROOT/scripts/org/append-event.py"}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --task-id)
      task_id=${2:-}
      shift
      ;;
    --run-id)
      run_id=${2:-}
      shift
      ;;
    --worktree-path)
      worktree_path=${2:-}
      shift
      ;;
    --artifact-dir)
      artifact_dir=${2:-}
      shift
      ;;
    --stdout-source)
      stdout_source=${2:-}
      shift
      ;;
    --stderr-source)
      stderr_source=${2:-}
      shift
      ;;
    --last-message-source)
      last_message_source=${2:-}
      shift
      ;;
    --actor-role)
      actor_role=${2:-}
      shift
      ;;
    --actor-id)
      actor_id=${2:-}
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'collect-artifacts.sh: unknown option: %s\n' "$1" >&2
      usage
      exit 2
      ;;
  esac
  shift
done

missing=0
for value_name in task_id run_id worktree_path artifact_dir stdout_source stderr_source last_message_source actor_role actor_id; do
  if [ -z "${!value_name}" ]; then
    printf 'collect-artifacts.sh: missing required option for %s\n' "$value_name" >&2
    missing=1
  fi
done

if [ "$missing" -ne 0 ]; then
  usage
  exit 2
fi

mkdir -p "$artifact_dir/logs" "$artifact_dir/files/untracked" "$artifact_dir/files/generated" "$artifact_dir/audit"

python3 - "$task_id" "$run_id" "$worktree_path" "$artifact_dir" "$stdout_source" "$stderr_source" "$last_message_source" "$actor_role" "$actor_id" <<'PY'
from __future__ import annotations

import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


(
    TASK_ID,
    RUN_ID,
    WORKTREE_PATH,
    ARTIFACT_DIR,
    STDOUT_SOURCE,
    STDERR_SOURCE,
    LAST_MESSAGE_SOURCE,
    ACTOR_ROLE,
    ACTOR_ID,
) = sys.argv[1:10]

MAX_LOG_BYTES = 20 * 1024 * 1024
LOG_EDGE_BYTES = 10 * 1024 * 1024
MAX_FILE_BYTES = 50 * 1024 * 1024
MAX_TOTAL_BYTES = 200 * 1024 * 1024
EXCLUDED_PARTS = {".git", "node_modules", ".cache", ".next", "dist", "build", "coverage"}
GENERATED_EXTS = {".md", ".markdown", ".json", ".yaml", ".yml", ".txt"}

worktree_path = Path(WORKTREE_PATH).resolve()
artifact_dir = Path(ARTIFACT_DIR)
if not artifact_dir.is_absolute():
    artifact_dir = Path.cwd() / artifact_dir
artifact_dir = artifact_dir.resolve()
artifact_dir.mkdir(parents=True, exist_ok=True)

artifacts: list[dict[str, object]] = []
verification_errors: list[str] = []


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def run_git(args: list[str], *, cwd: Path | None = None) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        ["git", "-C", str(cwd or worktree_path), *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def rel_artifact(path: Path) -> str:
    return path.resolve().relative_to(artifact_dir).as_posix()


def current_total_size() -> int:
    total = 0
    for path in artifact_dir.rglob("*"):
        if path.is_file() and not path.is_symlink():
            total += path.stat().st_size
    return total


def add_artifact(
    *,
    artifact_id: str,
    kind: str,
    path: Path,
    required: bool,
    status_value: str = "captured",
    source_path: str | None = None,
    source_relpath: str | None = None,
    extra: dict[str, object] | None = None,
) -> None:
    if path.exists() and path.is_file():
        size = path.stat().st_size
        digest = sha256_file(path)
        mode = oct(stat.S_IMODE(path.stat().st_mode))
    else:
        size = 0
        digest = hashlib.sha256(b"").hexdigest()
        mode = None

    entry: dict[str, object] = {
        "id": artifact_id,
        "kind": kind,
        "artifact_path": rel_artifact(path),
        "size_bytes": size,
        "sha256": digest,
        "required": required,
        "status": status_value,
        "captured_at": now_iso(),
    }
    if source_path is not None:
        entry["source_path"] = source_path
    if source_relpath is not None:
        entry["source_relpath"] = source_relpath
    if mode is not None:
        entry["mode"] = mode
    if extra:
        entry.update(extra)
    artifacts.append(entry)


def copy_regular(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    if src.resolve() == dst.resolve():
        return
    shutil.copyfile(src, dst)


def copy_log(src_raw: str, dst_rel: str, kind: str) -> None:
    src = Path(src_raw)
    dst = artifact_dir / dst_rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    if not src.is_file():
        dst.write_bytes(b"")
        add_artifact(
            artifact_id=kind,
            kind=kind,
            path=dst,
            required=True,
            status_value="missing",
            source_path=str(src),
        )
        verification_errors.append(f"missing required {kind} source: {src}")
        return

    size = src.stat().st_size
    if size > MAX_LOG_BYTES:
        tmp_dst = dst.with_suffix(dst.suffix + ".tmp") if src.resolve() == dst.resolve() else dst
        with src.open("rb") as source, tmp_dst.open("wb") as target:
            target.write(source.read(LOG_EDGE_BYTES))
            source.seek(max(size - LOG_EDGE_BYTES, 0))
            target.write(source.read(LOG_EDGE_BYTES))
        if tmp_dst != dst:
            tmp_dst.replace(dst)
        add_artifact(
            artifact_id=kind,
            kind="truncated_log",
            path=dst,
            required=True,
            source_path=str(src),
            extra={
                "truncation": {
                    "original_size_bytes": size,
                    "stored_size_bytes": dst.stat().st_size,
                    "reason": f"{kind} exceeded max_log_bytes",
                }
            },
        )
        return

    copy_regular(src, dst)
    add_artifact(artifact_id=kind, kind=kind, path=dst, required=True, source_path=str(src))


def write_command_artifact(args: list[str], dst_rel: str, artifact_id: str, kind: str) -> None:
    dst = artifact_dir / dst_rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    result = run_git(args)
    dst.write_bytes(result.stdout)
    add_artifact(artifact_id=artifact_id, kind=kind, path=dst, required=True)
    if result.returncode != 0:
        stderr_text = result.stderr.decode("utf-8", errors="replace").strip()
        verification_errors.append(f"git {' '.join(args)} failed: {stderr_text}")


def excluded(rel: str) -> bool:
    parts = Path(rel).parts
    return any(part in EXCLUDED_PARTS for part in parts)


def copy_untracked() -> None:
    result = run_git(["ls-files", "--others", "--exclude-standard", "-z"])
    if result.returncode != 0:
        verification_errors.append(
            "git ls-files --others failed: "
            + result.stderr.decode("utf-8", errors="replace").strip()
        )
        return

    for rel_bytes in result.stdout.split(b"\0"):
        if not rel_bytes:
            continue
        rel = rel_bytes.decode("utf-8", errors="surrogateescape")
        if excluded(rel):
            continue

        src = worktree_path / rel
        if not src.exists() and not src.is_symlink():
            continue

        if src.is_symlink():
            dst = artifact_dir / "files" / "untracked" / f"{rel}.symlink-target"
            dst.parent.mkdir(parents=True, exist_ok=True)
            target = os.readlink(src)
            dst.write_text(target + "\n", encoding="utf-8")
            add_artifact(
                artifact_id=f"symlink:{rel}",
                kind="symlink_metadata",
                path=dst,
                required=False,
                source_path=str(src),
                source_relpath=rel,
                extra={"symlink": {"target": target, "followed": False}},
            )
            continue

        if not src.is_file():
            continue

        size = src.stat().st_size
        if size > MAX_FILE_BYTES or current_total_size() + size > MAX_TOTAL_BYTES:
            metadata_dst = artifact_dir / "files" / "untracked" / f"{rel}.skipped.json"
            metadata_dst.parent.mkdir(parents=True, exist_ok=True)
            metadata_dst.write_text(
                json.dumps(
                    {
                        "source_relpath": rel,
                        "size_bytes": size,
                        "reason": "file exceeded artifact collection limits",
                    },
                    indent=2,
                    sort_keys=True,
                )
                + "\n",
                encoding="utf-8",
            )
            add_artifact(
                artifact_id=f"skipped:{rel}",
                kind="skipped_large_file",
                path=metadata_dst,
                required=False,
                status_value="skipped",
                source_path=str(src),
                source_relpath=rel,
            )
            continue

        is_generated = src.suffix.lower() in GENERATED_EXTS
        base_dir = "generated" if is_generated else "untracked"
        dst = artifact_dir / "files" / base_dir / rel
        copy_regular(src, dst)
        add_artifact(
            artifact_id=f"{base_dir}:{rel}",
            kind="generated_file" if is_generated else "untracked_file",
            path=dst,
            required=False,
            source_path=str(src),
            source_relpath=rel,
        )


def git_text(args: list[str], default: str = "") -> str:
    result = run_git(args)
    if result.returncode != 0:
        return default
    return result.stdout.decode("utf-8", errors="replace").strip()


copy_log(STDOUT_SOURCE, "logs/stdout.log", "stdout")
copy_log(STDERR_SOURCE, "logs/stderr.log", "stderr")

last_message_src = Path(LAST_MESSAGE_SOURCE)
last_message_dst = artifact_dir / "output-last-message.txt"
if last_message_src.is_file():
    copy_regular(last_message_src, last_message_dst)
    add_artifact(
        artifact_id="output-last-message",
        kind="output_last_message",
        path=last_message_dst,
        required=True,
        source_path=str(last_message_src),
    )
else:
    last_message_dst.write_bytes(b"")
    add_artifact(
        artifact_id="output-last-message",
        kind="output_last_message",
        path=last_message_dst,
        required=True,
        status_value="missing",
        source_path=str(last_message_src),
    )
    verification_errors.append(f"missing required output-last-message source: {last_message_src}")

write_command_artifact(["status", "--porcelain=v1"], "git-status.txt", "git-status", "git_status")
write_command_artifact(["diff", "--binary"], "git-diff.patch", "git-diff", "git_diff")
write_command_artifact(
    ["diff", "--cached", "--binary"],
    "git-diff-cached.patch",
    "git-diff-cached",
    "git_diff_cached",
)
copy_untracked()

repo_root = os.environ.get("ORGOS_REPO_ROOT") or git_text(
    ["rev-parse", "--show-toplevel"], str(worktree_path)
)
head_after = git_text(["rev-parse", "HEAD"], "")
head_before = os.environ.get("ORGOS_HEAD_BEFORE") or head_after
branch = git_text(["rev-parse", "--abbrev-ref", "HEAD"], "HEAD")
dirty_after = bool((artifact_dir / "git-status.txt").read_text(encoding="utf-8"))
created_at = now_iso()
verified = not verification_errors

manifest = {
    "schema_version": "orgos.artifact_manifest.v1",
    "project_id": os.environ.get("ORGOS_PROJECT_ID") or Path(repo_root).name,
    "task_id": TASK_ID,
    "run_id": RUN_ID,
    "created_at": created_at,
    "repo": {
        "repo_root": repo_root,
        "worktree_path": str(worktree_path),
        "branch": branch,
        "head_before": head_before,
        "head_after": head_after,
        "dirty_after": dirty_after,
    },
    "actor": {
        "role": ACTOR_ROLE,
        "id": ACTOR_ID,
        "model": os.environ.get("ORGOS_ACTOR_MODEL", ""),
        "session_id": os.environ.get("ORGOS_SESSION_ID", ""),
    },
    "execution": {
        "command_label": os.environ.get("ORGOS_COMMAND_LABEL", "codex"),
        "started_at": os.environ.get("ORGOS_EXEC_STARTED_AT", created_at),
        "ended_at": os.environ.get("ORGOS_EXEC_ENDED_AT", created_at),
        "exit_code": int(os.environ.get("ORGOS_EXEC_EXIT_CODE", "0")),
        "wrapper_version": os.environ.get("ORGOS_WRAPPER_VERSION", "day1-artifact-manifest"),
    },
    "artifacts": artifacts,
    "limits": {
        "max_log_bytes": MAX_LOG_BYTES,
        "max_file_bytes": MAX_FILE_BYTES,
        "max_total_bytes": MAX_TOTAL_BYTES,
    },
    "verification": {
        "verified": verified,
        "verified_at": now_iso(),
        "errors": verification_errors,
    },
    "cleanup": {
        "cleanup_allowed": verified,
        "cleanup_reason": "artifact manifest captured and internally verified"
        if verified
        else "artifact collection errors",
        "cleanup_status": "pending",
    },
}

manifest_path = artifact_dir / "artifact_manifest.json"
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
manifest_sha_path = artifact_dir / "artifact_manifest.sha256"
manifest_sha_path.write_text(
    f"{sha256_file(manifest_path)}  artifact_manifest.json\n",
    encoding="utf-8",
)

if verification_errors:
    for error in verification_errors:
        print(error, file=sys.stderr)
    sys.exit(1)
PY

manifest_path=$(python3 - "$artifact_dir" <<'PY'
from pathlib import Path
import sys

artifact_dir = Path(sys.argv[1])
if not artifact_dir.is_absolute():
    artifact_dir = Path.cwd() / artifact_dir
print((artifact_dir.resolve() / "artifact_manifest.json").as_posix())
PY
)

artifact_count=$(python3 - "$manifest_path" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    manifest = json.load(handle)
print(len(manifest.get("artifacts", [])))
PY
)

if [ -f "$APPEND_EVENT" ]; then
  payload_json=$(python3 - "$run_id" "$manifest_path" "$artifact_count" <<'PY'
import json
import sys

run_id, manifest_path, artifact_count = sys.argv[1:4]
payload = {
    "run_id": run_id,
    "manifest_path": manifest_path,
    "artifact_count": int(artifact_count),
}
sys.stdout.write(json.dumps(payload, sort_keys=True))
PY
)
  python3 "$APPEND_EVENT" \
    --event-type ArtifactCollected \
    --task-id "$task_id" \
    --actor-role system \
    --actor-id collect-artifacts.sh \
    --payload-json "$payload_json" >/dev/null || true
fi
