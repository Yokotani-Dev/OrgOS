#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

bash "$SCRIPT_DIR/test-day0-cleanup.sh"
bash "$SCRIPT_DIR/test-day1-manifest.sh"
bash "$SCRIPT_DIR/test-policy-core.sh"
bash "$SCRIPT_DIR/test-day2-policy.sh"
bash "$SCRIPT_DIR/test-week2-integrator.sh"
bash "$SCRIPT_DIR/test-week2-yaml.sh"
bash "$SCRIPT_DIR/test-week3-lease.sh"
bash "$SCRIPT_DIR/test-context-pack.sh"
bash "$SCRIPT_DIR/test-archive-tasks.sh"
bash "$SCRIPT_DIR/test-deploy-kernel-v2.sh"
bash "$SCRIPT_DIR/test-org-brief-journey.sh"
bash "$SCRIPT_DIR/test-secret-management.sh"
bash "$SCRIPT_DIR/test-doc-generators.sh"
