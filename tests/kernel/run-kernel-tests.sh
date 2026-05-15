#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

bash "$SCRIPT_DIR/test-day0-cleanup.sh"
bash "$SCRIPT_DIR/test-day1-manifest.sh"
bash "$SCRIPT_DIR/test-day2-policy.sh"
bash "$SCRIPT_DIR/test-week2-integrator.sh"
