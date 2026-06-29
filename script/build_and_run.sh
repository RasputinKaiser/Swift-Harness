#!/usr/bin/env bash
# build_and_run.sh — Bootstrap contract for the HarnessApp macOS SwiftUI app.
# Builds via SwiftPM and launches the resulting executable.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN_NAME="HarnessApp"

echo "=== building $BIN_NAME via SwiftPM ==="
cd "$REPO_ROOT"
swift build 2>&1 | sed 's/^/  /'

BIN_PATH="$REPO_ROOT/.build/debug/$BIN_NAME"
if [ ! -x "$BIN_PATH" ]; then
  echo "ERR: executable not found at $BIN_PATH" >&2
  exit 1
fi

echo "=== launching ==="
exec "$BIN_PATH"