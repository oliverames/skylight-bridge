#!/usr/bin/env bash
set -euo pipefail

APP_NAME="SkylightBridge"
DISPLAY_NAME="Skylight Bridge"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Oliver Ames (PV3W52NDZ3)}"
DEVELOPER_ID_PROFILE="${DEVELOPER_ID_PROFILE:-}"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-notarytool-profile}"

APP_BUNDLE_IDENTIFIER="com.oliverames.SkylightBridge"
CLOUDKIT_CONTAINER_IDENTIFIER="iCloud.com.oliverames.SkylightBridge"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SOURCE_INFO_PLIST")}"
BUILD_NUMBER="${BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$SOURCE_INFO_PLIST")}"
RELEASE_DIR="$ROOT_DIR/dist/release"
APP_BUNDLE="$RELEASE_DIR/$DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENTITLEMENTS="$ROOT_DIR/Resources/SkylightBridge.entitlements"
RESOLVED_ENTITLEMENTS="$RELEASE_DIR/SkylightBridge.resolved.entitlements"
ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.icon"
SPARKLE_FRAMEWORK_SOURCE="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
SPARKLE_FRAMEWORK="$APP_FRAMEWORKS/Sparkle.framework"
APP_ZIP="$RELEASE_DIR/$DISPLAY_NAME-$VERSION.zip"
DMG_PATH="$RELEASE_DIR/$DISPLAY_NAME-$VERSION.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"
DMG_SOURCE="$RELEASE_DIR/dmg-source"
DMG_MOUNT="$RELEASE_DIR/dmg-mount"

require_notary_credentials() {
  if [[ -n "${NOTARY_KEY_FILE:-}" || -n "${NOTARY_KEY_ID:-}" || -n "${NOTARY_ISSUER_ID:-}" ]]; then
    : "${NOTARY_KEY_FILE:?Set NOTARY_KEY_FILE to an App Store Connect API key file}"
    : "${NOTARY_KEY_ID:?Set NOTARY_KEY_ID to the App Store Connect key ID}"
    : "${NOTARY_ISSUER_ID:?Set NOTARY_ISSUER_ID to the App Store Connect issuer ID}"
    NOTARYTOOL_ARGS=(
      --key "$NOTARY_KEY_FILE"
      --key-id "$NOTARY_KEY_ID"
      --issuer "$NOTARY_ISSUER_ID"
    )
    return
  fi

  if ! xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" >/dev/null 2>&1; then
    echo "No usable notarization credentials. Set NOTARY_KEY_FILE, NOTARY_KEY_ID, and NOTARY_ISSUER_ID, or configure keychain profile '$KEYCHAIN_PROFILE'." >&2
    exit 1
  fi
  NOTARYTOOL_ARGS=(--keychain-profile "$KEYCHAIN_PROFILE")
}

require_developer_id_profile() {
  : "${DEVELOPER_ID_PROFILE:?Set DEVELOPER_ID_PROFILE to the CloudKit-enabled Developer ID provisioning profile}"
  if [[ ! -r "$DEVELOPER_ID_PROFILE" ]]; then
    echo "Developer ID provisioning profile is not readable: $DEVELOPER_ID_PROFILE" >&2
    exit 1
  fi

  local profile_app_identifier
  profile_app_identifier="$(
    security cms -D -i "$DEVELOPER_ID_PROFILE" | /usr/bin/python3 -c '
import plistlib
import sys

entitlements = plistlib.loads(sys.stdin.buffer.read())["Entitlements"]
print(
    entitlements.get("com.apple.application-identifier")
    or entitlements.get("application-identifier", "")
)
'
  )"
  if [[ "$profile_app_identifier" != *."$APP_BUNDLE_IDENTIFIER" ]]; then
    echo "Developer ID provisioning profile does not authorize $APP_BUNDLE_IDENTIFIER" >&2
    exit 1
  fi

  local profile_cloudkit_container
  profile_cloudkit_container="$(
    security cms -D -i "$DEVELOPER_ID_PROFILE" | /usr/bin/python3 -c '
import plistlib
import sys

container_identifier = sys.argv[1]
entitlements = plistlib.loads(sys.stdin.buffer.read())["Entitlements"]
containers = entitlements.get("com.apple.developer.icloud-container-identifiers", [])
if container_identifier in containers:
    print(container_identifier)
' "$CLOUDKIT_CONTAINER_IDENTIFIER"
  )"
  if [[ "$profile_cloudkit_container" != "$CLOUDKIT_CONTAINER_IDENTIFIER" ]]; then
    echo "Developer ID provisioning profile does not authorize $CLOUDKIT_CONTAINER_IDENTIFIER" >&2
    exit 1
  fi
}

submit_for_notarization() {
  local artifact="$1"
  xcrun notarytool submit "$artifact" "${NOTARYTOOL_ARGS[@]}" --wait
}

: "${CLOUDKIT_SCHEMA_FILE:?Set CLOUDKIT_SCHEMA_FILE to a fresh production CloudKit schema export}"
python3 "$ROOT_DIR/script/validate_cloudkit_schema.py" "$CLOUDKIT_SCHEMA_FILE"
require_notary_credentials
require_developer_id_profile

rm -rf "$RELEASE_DIR"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_FRAMEWORKS"

cd "$ROOT_DIR"
swift build -c release --arch arm64 --arch x86_64
BUILD_BINARY="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$APP_NAME"

cp "$BUILD_BINARY" "$APP_BINARY"
chmod 755 "$APP_BINARY"
if [[ ! -d "$SPARKLE_FRAMEWORK_SOURCE" ]]; then
  echo "Sparkle framework is missing. Run 'swift package resolve' before building a release." >&2
  exit 1
fi
ditto "$SPARKLE_FRAMEWORK_SOURCE" "$SPARKLE_FRAMEWORK"
if ! otool -l "$APP_BINARY" | awk '
  $1 == "path" && $2 == "@executable_path/../Frameworks" { found = 1 }
  END { exit !found }
'; then
  install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP_BINARY"
fi
cp "$ROOT_DIR/Resources/Info.plist" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFO_PLIST"
cp "$DEVELOPER_ID_PROFILE" "$APP_CONTENTS/embedded.provisionprofile"
"$ROOT_DIR/script/compile_app_icon.sh" "$ICON_SOURCE" "$APP_RESOURCES" "$INFO_PLIST"

plutil -lint "$INFO_PLIST" >/dev/null
plutil -lint "$ENTITLEMENTS" >/dev/null
"$ROOT_DIR/script/resolve_cloudkit_entitlements.sh" \
  "$ENTITLEMENTS" \
  "$DEVELOPER_ID_PROFILE" \
  "$RESOLVED_ENTITLEMENTS" \
  "$APP_BUNDLE_IDENTIFIER" \
  "$CLOUDKIT_CONTAINER_IDENTIFIER"
lipo "$APP_BINARY" -verify_arch arm64
lipo "$APP_BINARY" -verify_arch x86_64
if ! otool -L "$APP_BINARY" | rg -Fq '@rpath/Sparkle.framework/Versions/B/Sparkle'; then
  echo "release binary does not link Sparkle.framework" >&2
  exit 1
fi
if ! otool -l "$APP_BINARY" | awk '
  $1 == "path" && $2 == "@executable_path/../Frameworks" { found = 1 }
  END { exit !found }
'; then
  echo "release binary does not search the app's Frameworks directory" >&2
  exit 1
fi

SPARKLE_VERSION_DIR="$SPARKLE_FRAMEWORK/Versions/B"
if [[ -d "$SPARKLE_VERSION_DIR/XPCServices/Installer.xpc" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp \
    "$SPARKLE_VERSION_DIR/XPCServices/Installer.xpc"
fi
if [[ -d "$SPARKLE_VERSION_DIR/XPCServices/Downloader.xpc" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp \
    --preserve-metadata=entitlements \
    "$SPARKLE_VERSION_DIR/XPCServices/Downloader.xpc"
fi
if [[ -f "$SPARKLE_VERSION_DIR/Autoupdate" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp \
    "$SPARKLE_VERSION_DIR/Autoupdate"
fi
if [[ -d "$SPARKLE_VERSION_DIR/Updater.app" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp \
    "$SPARKLE_VERSION_DIR/Updater.app"
fi
codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$SPARKLE_FRAMEWORK"
codesign --verify --strict --verbose=4 "$SPARKLE_FRAMEWORK"

codesign \
  --force \
  --sign "$SIGN_IDENTITY" \
  --options runtime \
  --timestamp \
  --entitlements "$RESOLVED_ENTITLEMENTS" \
  "$APP_BUNDLE"

codesign --verify --deep --strict --verbose=4 "$APP_BUNDLE"
codesign -d --entitlements :- "$APP_BUNDLE" 2>/dev/null > "$RELEASE_DIR/runtime-entitlements.plist"
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' \
  "$RELEASE_DIR/runtime-entitlements.plist" 2>/dev/null | rg -Fxq true; then
  echo "release app contains get-task-allow" >&2
  exit 1
fi

for entitlement_key in \
  com.apple.application-identifier \
  com.apple.developer.team-identifier \
  com.apple.developer.icloud-container-environment; do
  expected_value="$(/usr/libexec/PlistBuddy -c "Print :$entitlement_key" "$RESOLVED_ENTITLEMENTS")"
  actual_value="$(/usr/libexec/PlistBuddy -c "Print :$entitlement_key" "$RELEASE_DIR/runtime-entitlements.plist")"
  if [[ "$actual_value" != "$expected_value" ]]; then
    echo "release app entitlement mismatch for $entitlement_key" >&2
    exit 1
  fi
done

ditto -c -k --keepParent "$APP_BUNDLE" "$APP_ZIP"

submit_for_notarization "$APP_ZIP"
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"
spctl -a -vvv --type execute "$APP_BUNDLE"

mkdir -p "$DMG_SOURCE"
ditto "$APP_BUNDLE" "$DMG_SOURCE/$DISPLAY_NAME.app"
ln -s /Applications "$DMG_SOURCE/Applications"
diskutil image create from \
  --format UDZO \
  --volumeName "$DISPLAY_NAME" \
  "$DMG_SOURCE" \
  "$DMG_PATH"

codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
submit_for_notarization "$DMG_PATH"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
hdiutil verify "$DMG_PATH"
spctl -a -vvv -t open --context context:primary-signature "$DMG_PATH"

mkdir -p "$DMG_MOUNT"
diskutil image attach --readOnly --nobrowse --mountPoint "$DMG_MOUNT" "$DMG_PATH"
trap 'diskutil eject "$DMG_MOUNT" >/dev/null 2>&1 || true' EXIT
codesign --verify --deep --strict --verbose=4 "$DMG_MOUNT/$DISPLAY_NAME.app"
spctl -a -vvv --type execute "$DMG_MOUNT/$DISPLAY_NAME.app"
diskutil eject "$DMG_MOUNT"
trap - EXIT
rmdir "$DMG_MOUNT"

(
  cd "$RELEASE_DIR"
  shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$CHECKSUM_PATH")"
)
rm -rf "$DMG_SOURCE" "$APP_ZIP"

printf 'Release artifacts:\n%s\n%s\n' "$DMG_PATH" "$CHECKSUM_PATH"
