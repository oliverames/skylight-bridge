#!/bin/bash
set -euo pipefail

fixture_repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_directory="$(mktemp -d "${TMPDIR:-/tmp}/skylight-integrity.XXXXXX")"
trap 'rm -rf "$fixture_directory"' EXIT

# Compile only the authenticator and memory fixtures. Never initialize AppStore,
# PhotoKit, a production file store, or an account-based Keychain authenticator.
xcrun swiftc -swift-version 6 -enable-upcoming-feature ApproachableConcurrency \
  -parse-as-library -module-cache-path "$fixture_directory/Module Cache" \
  "$fixture_repo/Sources/SkylightBridge/Services/LocalFileAuthenticator.swift" \
  "$fixture_repo/Tests/LocalFileAuthenticatorFixtureTests.swift" \
  -o "$fixture_directory/LocalFileAuthenticatorFixtures"
"$fixture_directory/LocalFileAuthenticatorFixtures"
