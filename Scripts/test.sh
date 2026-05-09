#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CACHE_PATH="${HOME}/Library/Caches/RepoBar/swiftpm"
mkdir -p "${CACHE_PATH}"

./Scripts/swiftpm_sanitize.sh

echo "==> swift test"
swift test -q --cache-path "${CACHE_PATH}" "$@"
