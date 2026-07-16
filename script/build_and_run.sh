#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="SkylightBridge"
DISPLAY_NAME="Skylight Bridge"
BUNDLE_ID="com.oliverames.SkylightBridge"
CLOUDKIT_CONTAINER_IDENTIFIER="iCloud.com.oliverames.SkylightBridge"
DEVELOPER_ID_PROFILE="${DEVELOPER_ID_PROFILE:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_FILE="$ROOT_DIR/Resources/AppIcon.icon"
ENTITLEMENTS_FILE="$ROOT_DIR/Resources/SkylightBridge.entitlements"
RESOLVED_ENTITLEMENTS_FILE="$DIST_DIR/SkylightBridge.resolved.entitlements"
INFO_PLIST_TEMPLATE="$ROOT_DIR/Resources/Info.plist"

if [[ -z "$DEVELOPER_ID_PROFILE" ]]; then
  installed_profile="/Applications/$DISPLAY_NAME.app/Contents/embedded.provisionprofile"
  if [[ -r "$installed_profile" ]]; then
    DEVELOPER_ID_PROFILE="$installed_profile"
  fi
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
swift build
BUILD_PRODUCTS="$(swift build --show-bin-path)"
BUILD_BINARY="$BUILD_PRODUCTS/$APP_NAME"
SPARKLE_FRAMEWORK_SOURCE="$BUILD_PRODUCTS/PackageFrameworks/Sparkle.framework"
SPARKLE_FRAMEWORK="$APP_FRAMEWORKS/Sparkle.framework"

if [[ ! -d "$SPARKLE_FRAMEWORK_SOURCE" ]]; then
  echo "Sparkle.framework is missing from the Swift package build." >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_FRAMEWORKS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
ditto "$SPARKLE_FRAMEWORK_SOURCE" "$SPARKLE_FRAMEWORK"

if ! otool -l "$APP_BINARY" | awk '
  $1 == "path" && $2 == "@executable_path/../Frameworks" { found = 1 }
  END { exit !found }
'; then
  install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP_BINARY"
fi

cp "$INFO_PLIST_TEMPLATE" "$INFO_PLIST"

"$ROOT_DIR/script/compile_app_icon.sh" "$ICON_FILE" "$APP_RESOURCES" "$INFO_PLIST"

plutil -lint "$INFO_PLIST" >/dev/null
plutil -lint "$ENTITLEMENTS_FILE" >/dev/null

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$CODESIGN_IDENTITY" ]] && security find-identity -v -p codesigning | rg -Fq "Developer ID Application: Oliver Ames (PV3W52NDZ3)"; then
  CODESIGN_IDENTITY="Developer ID Application: Oliver Ames (PV3W52NDZ3)"
fi

if [[ -n "$CODESIGN_IDENTITY" ]]; then
  if [[ -z "$DEVELOPER_ID_PROFILE" ]]; then
    echo "Developer ID signing with CloudKit requires DEVELOPER_ID_PROFILE." >&2
    exit 1
  fi
  if [[ ! -r "$DEVELOPER_ID_PROFILE" ]]; then
    echo "Developer ID provisioning profile is not readable: $DEVELOPER_ID_PROFILE" >&2
    exit 1
  fi
  cp "$DEVELOPER_ID_PROFILE" "$APP_CONTENTS/embedded.provisionprofile"
  "$ROOT_DIR/script/resolve_cloudkit_entitlements.sh" \
    "$ENTITLEMENTS_FILE" \
    "$DEVELOPER_ID_PROFILE" \
    "$RESOLVED_ENTITLEMENTS_FILE" \
    "$BUNDLE_ID" \
    "$CLOUDKIT_CONTAINER_IDENTIFIER"
  codesign \
    --force \
    --sign "$CODESIGN_IDENTITY" \
    --options runtime \
    --timestamp \
    "$SPARKLE_FRAMEWORK" >/dev/null
  codesign \
    --force \
    --sign "$CODESIGN_IDENTITY" \
    --options runtime \
    --timestamp \
    --entitlements "$RESOLVED_ENTITLEMENTS_FILE" \
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
