#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

bash "$SCRIPT_DIR/test-day0-cleanup.sh"
bash "$SCRIPT_DIR/test-day1-manifest.sh"
