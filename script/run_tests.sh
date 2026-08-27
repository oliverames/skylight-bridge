#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE_FRAMEWORK="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

cd "$ROOT_DIR"
bash script/test_appcast_helpers.sh
swift build --build-tests

if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
  echo "Sparkle.framework is missing. Run 'swift package resolve' and retry." >&2
  exit 1
fi

DEBUG_BIN_DIR="$(swift build --show-bin-path)"
PACKAGE_FRAMEWORKS="$DEBUG_BIN_DIR/PackageFrameworks"
mkdir -p "$PACKAGE_FRAMEWORKS"
rm -rf "$PACKAGE_FRAMEWORKS/Sparkle.framework"
ditto "$SPARKLE_FRAMEWORK" "$PACKAGE_FRAMEWORKS/Sparkle.framework"

swift test --skip-build
