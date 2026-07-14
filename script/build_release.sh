#!/usr/bin/env bash
set -euo pipefail

APP_NAME="SkylightBridge"
DISPLAY_NAME="Skylight Bridge"
VERSION="${VERSION:-1.2.0}"
BUILD_NUMBER="${BUILD_NUMBER:-3}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Oliver Ames (PV3W52NDZ3)}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/dist/release"
APP_BUNDLE="$RELEASE_DIR/$DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENTITLEMENTS="$ROOT_DIR/Resources/SkylightBridge.entitlements"
ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.png"
APP_ZIP="$RELEASE_DIR/$DISPLAY_NAME-$VERSION.zip"
DMG_PATH="$RELEASE_DIR/$DISPLAY_NAME-$VERSION.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"
DMG_SOURCE="$RELEASE_DIR/dmg-source"
DMG_MOUNT="$RELEASE_DIR/dmg-mount"

require_notary_credentials() {
  : "${NOTARY_KEY_FILE:?Set NOTARY_KEY_FILE to an App Store Connect API key file}"
  : "${NOTARY_KEY_ID:?Set NOTARY_KEY_ID to the App Store Connect key ID}"
  : "${NOTARY_ISSUER_ID:?Set NOTARY_ISSUER_ID to the App Store Connect issuer ID}"
}

submit_for_notarization() {
  local artifact="$1"
  xcrun notarytool submit "$artifact" \
    --key "$NOTARY_KEY_FILE" \
    --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER_ID" \
    --wait
}

rm -rf "$RELEASE_DIR"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"

cd "$ROOT_DIR"
swift build -c release --arch arm64 --arch x86_64 -Xswiftc -warnings-as-errors
BUILD_BINARY="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$APP_NAME"

cp "$BUILD_BINARY" "$APP_BINARY"
chmod 755 "$APP_BINARY"
cp "$ROOT_DIR/Resources/Info.plist" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFO_PLIST"
"$ROOT_DIR/script/create_icns.sh" "$ICON_SOURCE" "$APP_RESOURCES/AppIcon.icns"

plutil -lint "$INFO_PLIST" >/dev/null
plutil -lint "$ENTITLEMENTS" >/dev/null
lipo "$APP_BINARY" -verify_arch arm64
lipo "$APP_BINARY" -verify_arch x86_64

codesign \
  --force \
  --sign "$SIGN_IDENTITY" \
  --options runtime \
  --timestamp \
  --entitlements "$ENTITLEMENTS" \
  "$APP_BUNDLE"

codesign --verify --deep --strict --verbose=4 "$APP_BUNDLE"
codesign -d --entitlements - "$APP_BUNDLE" 2>&1 \
  | tee "$RELEASE_DIR/entitlements.txt" >/dev/null
if rg -q "get-task-allow" "$RELEASE_DIR/entitlements.txt"; then
  echo "release app contains get-task-allow" >&2
  exit 1
fi

ditto -c -k --keepParent "$APP_BUNDLE" "$APP_ZIP"

require_notary_credentials
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
