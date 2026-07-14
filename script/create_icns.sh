#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 INPUT_1024_PNG OUTPUT_ICNS" >&2
  exit 2
fi

INPUT_PNG="$1"
OUTPUT_ICNS="$2"
ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
trap 'rm -rf "${ICONSET_DIR%/AppIcon.iconset}"' EXIT

mkdir -p "$ICONSET_DIR" "$(dirname "$OUTPUT_ICNS")"
sips -z 16 16 "$INPUT_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$INPUT_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$INPUT_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$INPUT_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$INPUT_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$INPUT_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$INPUT_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$INPUT_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$INPUT_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$INPUT_PNG" "$ICONSET_DIR/icon_512x512@2x.png"
iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"
