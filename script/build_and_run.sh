#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="SkylightBridge"
DISPLAY_NAME="Skylight Bridge"
BUNDLE_ID="com.oliverames.SkylightBridge"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_FILE="$ROOT_DIR/Resources/AppIcon.png"
ENTITLEMENTS_FILE="$ROOT_DIR/Resources/SkylightBridge.entitlements"
INFO_PLIST_TEMPLATE="$ROOT_DIR/Resources/Info.plist"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

cp "$INFO_PLIST_TEMPLATE" "$INFO_PLIST"

if [[ -f "$ICON_FILE" ]]; then
  "$ROOT_DIR/script/create_icns.sh" "$ICON_FILE" "$APP_RESOURCES/AppIcon.icns"
fi

plutil -lint "$INFO_PLIST" >/dev/null
plutil -lint "$ENTITLEMENTS_FILE" >/dev/null

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$CODESIGN_IDENTITY" ]] && security find-identity -v -p codesigning | rg -Fq "Developer ID Application: Oliver Ames (PV3W52NDZ3)"; then
  CODESIGN_IDENTITY="Developer ID Application: Oliver Ames (PV3W52NDZ3)"
fi

if [[ -n "$CODESIGN_IDENTITY" ]]; then
  codesign \
    --force \
    --sign "$CODESIGN_IDENTITY" \
    --options runtime \
    --timestamp \
    --entitlements "$ENTITLEMENTS_FILE" \
    "$APP_BUNDLE" >/dev/null
else
  codesign --force --deep --sign - --timestamp=none "$APP_BUNDLE" >/dev/null
fi
codesign --verify --deep --strict "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
