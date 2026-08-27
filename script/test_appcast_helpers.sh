#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=appcast_helpers.sh
source "$SCRIPT_DIR/appcast_helpers.sh"

fail() {
  printf 'appcast helper test failed: %s\n' "$1" >&2
  exit 1
}

[[ "$(normalize_appcast_build 00027)" == "27" ]] || fail "leading zero normalization"
[[ "$(normalize_appcast_build 000)" == "0" ]] || fail "zero normalization"
is_newer_appcast_build 27 26 || fail "newer build accepted"
is_newer_appcast_build 100 99 || fail "different-width newer build accepted"
if is_newer_appcast_build 26 26; then fail "equal build accepted"; fi
if is_newer_appcast_build 25 26; then fail "older build accepted"; fi

escaped="$(escape_cdata 'before]]>after')"
[[ "$escaped" == 'before]]]]><![CDATA[>after' ]] || fail "CDATA terminator escaping"

fixture='<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:version>42</sparkle:version></item></channel></rss>'
[[ "$(current_appcast_build <(printf '%s' "$fixture"))" == "42" ]] \
  || fail "current build extraction"

printf 'Appcast helper tests passed.\n'
