#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: $0 VERSION BUILD_NUMBER DMG_PATH RELEASE_ASSET_NAME" >&2
  exit 2
fi

VERSION="$1"
BUILD_NUMBER="$2"
DMG_PATH="$3"
RELEASE_ASSET_NAME="$4"
REPOSITORY="oliverames/skylight-bridge"
APPCAST_URL="https://raw.githubusercontent.com/$REPOSITORY/gh-pages/appcast.xml"
KEYCHAIN_ACCOUNT="${SPARKLE_KEYCHAIN_ACCOUNT:-Skylight Bridge Sparkle EdDSA}"
APPCAST_DESCRIPTION="${APPCAST_DESCRIPTION:-This release includes improvements and fixes.}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPCAST_PATH="$ROOT_DIR/appcast.xml"
SIGN_TOOL="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/sign_update"
PAGES_DIR=""
TMP_APPCAST=""

cleanup() {
  local result=$?
  if [[ -n "$PAGES_DIR" && -d "$PAGES_DIR" ]]; then
    rm -rf "$PAGES_DIR"
  fi
  if [[ -n "$TMP_APPCAST" && -f "$TMP_APPCAST" ]]; then
    rm -f "$TMP_APPCAST"
  fi
  exit "$result"
}
trap cleanup EXIT

if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){2}$ ]]; then
  echo "VERSION must be a numeric marketing version, for example 1.5.2." >&2
  exit 1
fi
if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "BUILD_NUMBER must be numeric." >&2
  exit 1
fi
if [[ ! -f "$DMG_PATH" ]]; then
  echo "DMG does not exist: $DMG_PATH" >&2
  exit 1
fi
if [[ ! -x "$SIGN_TOOL" ]]; then
  echo "Sparkle sign_update is missing. Run 'swift package resolve' and retry." >&2
  exit 1
fi
if ! gh release view "v$VERSION" --repo "$REPOSITORY" --json assets \
  --jq '.assets[].name' | rg -Fxq "$RELEASE_ASSET_NAME"; then
  echo "GitHub release v$VERSION does not contain $RELEASE_ASSET_NAME." >&2
  exit 1
fi

SIGNATURE="$($SIGN_TOOL "$DMG_PATH" --account "$KEYCHAIN_ACCOUNT" -p | tr -d '\r\n')"
if [[ -z "$SIGNATURE" ]]; then
  echo "Sparkle archive signature is empty." >&2
  exit 1
fi
"$SIGN_TOOL" --verify --account "$KEYCHAIN_ACCOUNT" "$DMG_PATH" "$SIGNATURE" >/dev/null

DMG_SIZE="$(stat -f%z "$DMG_PATH")"
PUBLISHED_AT="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
DOWNLOAD_URL="https://github.com/$REPOSITORY/releases/download/v$VERSION/$RELEASE_ASSET_NAME"
TMP_APPCAST="$(mktemp -t skylight-bridge-appcast)"
mv "$TMP_APPCAST" "$TMP_APPCAST.xml"
TMP_APPCAST="$TMP_APPCAST.xml"

cat > "$TMP_APPCAST" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Skylight Bridge Updates</title>
    <link>$APPCAST_URL</link>
    <description>Signed updates for Skylight Bridge.</description>
    <language>en</language>
    <item>
      <title>Version $VERSION</title>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <description><![CDATA[<p>$APPCAST_DESCRIPTION</p>]]></description>
      <pubDate>$PUBLISHED_AT</pubDate>
      <enclosure url="$DOWNLOAD_URL" sparkle:edSignature="$SIGNATURE" length="$DMG_SIZE" type="application/octet-stream" />
    </item>
  </channel>
</rss>
EOF

"$SIGN_TOOL" "$TMP_APPCAST" --account "$KEYCHAIN_ACCOUNT" --disable-signing-warning
"$SIGN_TOOL" --verify --account "$KEYCHAIN_ACCOUNT" "$TMP_APPCAST" >/dev/null
mv "$TMP_APPCAST" "$APPCAST_PATH"

PAGES_DIR="$(mktemp -d -t skylight-bridge-pages)"
ORIGIN_URL="$(git -C "$ROOT_DIR" remote get-url origin)"
if git ls-remote --exit-code --heads "$ORIGIN_URL" gh-pages >/dev/null 2>&1; then
  git clone --quiet --depth 1 --branch gh-pages "$ORIGIN_URL" "$PAGES_DIR"
else
  git -C "$PAGES_DIR" init --quiet
  git -C "$PAGES_DIR" remote add origin "$ORIGIN_URL"
  git -C "$PAGES_DIR" switch --quiet --orphan gh-pages
fi

cp "$APPCAST_PATH" "$PAGES_DIR/appcast.xml"
git -C "$PAGES_DIR" add appcast.xml
if ! git -C "$PAGES_DIR" diff --cached --quiet; then
  git -C "$PAGES_DIR" commit -m "Publish Skylight Bridge $VERSION appcast"
  git -C "$PAGES_DIR" push origin HEAD:gh-pages
fi

printf 'Published signed appcast: %s\n' "$APPCAST_URL"
