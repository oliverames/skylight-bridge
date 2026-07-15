#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 INPUT_ICON OUTPUT_RESOURCES INFO_PLIST" >&2
  exit 2
fi

INPUT_ICON="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
OUTPUT_RESOURCES="$(mkdir -p "$2" && cd "$2" && pwd)"
INFO_PLIST="$(cd "$(dirname "$3")" && pwd)/$(basename "$3")"
ICON_NAME="$(basename "$INPUT_ICON" .icon)"
PARTIAL_INFO_PLIST="$(mktemp)"
trap 'rm -f "$PARTIAL_INFO_PLIST"' EXIT

xcrun actool "$INPUT_ICON" \
  --compile "$OUTPUT_RESOURCES" \
  --platform macosx \
  --minimum-deployment-target 26.0 \
  --app-icon "$ICON_NAME" \
  --output-partial-info-plist "$PARTIAL_INFO_PLIST"

/usr/libexec/PlistBuddy -c "Merge $PARTIAL_INFO_PLIST" "$INFO_PLIST"
test -f "$OUTPUT_RESOURCES/Assets.car"
test -f "$OUTPUT_RESOURCES/$ICON_NAME.icns"
