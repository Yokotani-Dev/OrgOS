#!/usr/bin/env python3
"""Verify an OrgOS artifact manifest and its captured files."""

from __future__ import annotations

import hashlib
import json
import os
import sys
from pathlib import Path, PurePosixPath


REQUIRED_TOP_LEVEL = (
    "schema_version",
    "project_id",
    "task_id",
    "run_id",
    "created_at",
    "repo",
    "actor",
    "execution",
    "artifacts",
    "verification",
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_artifact_path(raw_path: object, manifest_dir: Path) -> tuple[Path | None, str | None]:
    if not isinstance(raw_path, str) or not raw_path:
        return None, "artifact_path must be a non-empty string"

    if os.path.isabs(raw_path):
        return None, f"absolute artifact_path is forbidden: {raw_path}"

    posix_path = PurePosixPath(raw_path)
    if any(part == ".." for part in posix_path.parts):
        return None, f"artifact_path must not contain '..': {raw_path}"

    target = (manifest_dir / raw_path).resolve()
    try:
        target.relative_to(manifest_dir.resolve())
    except ValueError:
        return None, f"artifact_path escapes manifest directory: {raw_path}"

    return target, None


def verify(manifest_path: Path) -> list[str]:
    errors: list[str] = []
    manifest_dir = manifest_path.parent

    try:
        with manifest_path.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
    except Exception as exc:  # noqa: BLE001 - CLI should report parse failures plainly.
        return [f"failed to parse manifest JSON: {exc}"]

    if not isinstance(data, dict):
        return ["manifest must be a JSON object"]

    for key in REQUIRED_TOP_LEVEL:
        if key not in data:
            errors.append(f"missing required top-level field: {key}")

    if data.get("schema_version") != "orgos.artifact_manifest.v1":
        errors.append("schema_version must be orgos.artifact_manifest.v1")

    verification = data.get("verification")
    if not isinstance(verification, dict):
        errors.append("verification must be an object")
    elif verification.get("verified") is not True:
        errors.append("verification.verified must be true")

    artifacts = data.get("artifacts")
    if not isinstance(artifacts, list):
        errors.append("artifacts must be a list")
        return errors

    for index, artifact in enumerate(artifacts):
        prefix = f"artifacts[{index}]"
        if not isinstance(artifact, dict):
            errors.append(f"{prefix} must be an object")
            continue

        artifact_path, path_error = validate_artifact_path(
            artifact.get("artifact_path"), manifest_dir
        )
        if path_error:
            errors.append(f"{prefix}: {path_error}")
            continue

        required = artifact.get("required") is True
        status = artifact.get("status")
        if required and status in {"missing", "skipped", "truncated"}:
            errors.append(f"{prefix}: required artifact has invalid status: {status}")

        if status != "captured":
            continue

        if artifact_path is None or not artifact_path.is_file():
            errors.append(f"{prefix}: missing captured artifact: {artifact.get('artifact_path')}")
            continue

        actual_size = artifact_path.stat().st_size
        if artifact.get("size_bytes") != actual_size:
            errors.append(
                f"{prefix}: size mismatch for {artifact.get('artifact_path')}: "
                f"manifest={artifact.get('size_bytes')} actual={actual_size}"
            )

        expected_sha = artifact.get("sha256")
        actual_sha = sha256_file(artifact_path)
        if expected_sha != actual_sha:
            errors.append(
                f"{prefix}: sha256 mismatch for {artifact.get('artifact_path')}: "
                f"manifest={expected_sha} actual={actual_sha}"
            )

    return errors


def main(argv: list[str]) -> int:
    if len(argv) != 2 or argv[1] in {"-h", "--help"}:
        print("Usage: verify-artifact-manifest.py <manifest_path>", file=sys.stderr)
        return 0 if len(argv) == 2 else 2

    manifest_path = Path(argv[1])
    if not manifest_path.is_file():
        print(f"manifest missing: {manifest_path}", file=sys.stderr)
        return 1

    errors = verify(manifest_path)
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
