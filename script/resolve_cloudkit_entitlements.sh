#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "usage: $0 <base-entitlements> <provisioning-profile> <output-entitlements> <bundle-id> <container-id>" >&2
  exit 2
fi

BASE_ENTITLEMENTS="$1"
PROVISIONING_PROFILE="$2"
OUTPUT_ENTITLEMENTS="$3"
BUNDLE_IDENTIFIER="$4"
CLOUDKIT_CONTAINER_IDENTIFIER="$5"

if [[ ! -r "$BASE_ENTITLEMENTS" ]]; then
  echo "Base entitlements are not readable: $BASE_ENTITLEMENTS" >&2
  exit 1
fi

if [[ ! -r "$PROVISIONING_PROFILE" ]]; then
  echo "Provisioning profile is not readable: $PROVISIONING_PROFILE" >&2
  exit 1
fi

PROFILE_PLIST="$(mktemp "${TMPDIR:-/tmp}/skylight-bridge-profile.XXXXXX")"
trap 'rm -f "$PROFILE_PLIST"' EXIT

security cms -D -i "$PROVISIONING_PROFILE" > "$PROFILE_PLIST"

application_identifier="$(
  /usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$PROFILE_PLIST"
)"
team_identifier="$(
  /usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.team-identifier' "$PROFILE_PLIST"
)"
cloudkit_environment="$(
  /usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.icloud-container-environment' "$PROFILE_PLIST"
)"

case "$application_identifier" in
  *."$BUNDLE_IDENTIFIER")
    ;;
  *)
    echo "Provisioning profile does not authorize $BUNDLE_IDENTIFIER" >&2
    exit 1
    ;;
esac

if ! /usr/libexec/PlistBuddy \
  -c 'Print :Entitlements:com.apple.developer.icloud-container-identifiers' \
  "$PROFILE_PLIST" | rg -Fq "$CLOUDKIT_CONTAINER_IDENTIFIER"; then
  echo "Provisioning profile does not authorize $CLOUDKIT_CONTAINER_IDENTIFIER" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_ENTITLEMENTS")"
cp "$BASE_ENTITLEMENTS" "$OUTPUT_ENTITLEMENTS"

set_string_entitlement() {
  local key="$1"
  local value="$2"
  /usr/libexec/PlistBuddy -c "Delete :$key" "$OUTPUT_ENTITLEMENTS" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :$key string $value" "$OUTPUT_ENTITLEMENTS"
}

# Xcode adds these profile-backed entitlements during normal macOS signing.
# The release scripts sign manually, so they must carry the app identity that
# CloudKit uses to associate the container with this process.
set_string_entitlement "com.apple.application-identifier" "$application_identifier"
set_string_entitlement "com.apple.developer.team-identifier" "$team_identifier"
set_string_entitlement "com.apple.developer.icloud-container-environment" "$cloudkit_environment"

plutil -lint "$OUTPUT_ENTITLEMENTS" >/dev/null
