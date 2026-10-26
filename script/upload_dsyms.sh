#!/usr/bin/env bash
# Upload a release build's debug symbols to Sentry, confirm Sentry lists every
# one, and create and finalize the matching Sentry release.
#
#   script/upload_dsyms.sh RELEASE_NAME DSYM [DSYM ...]
#
# RELEASE_NAME must match CrashReporting's releaseName
# (com.oliverames.SkylightBridge@VERSION+BUILD). The token is the organization
# token in 1Password, read with `op read` into this process's environment
# only, as Ping Warden's release.sh does. It never goes on a command line, in a
# file or in the output.
set -euo pipefail

SENTRY_ORG=ames-consulting-llc
SENTRY_PROJECT=skylight-bridge
TOKEN_REF='op://Development/PingWarden Sentry API Token/credential'

if (( $# < 2 )); then
  echo "usage: $(basename "$0") RELEASE_NAME DSYM [DSYM ...]" >&2
  exit 64
fi
release="$1"
shift

export PATH="$HOME/.local/bin:$PATH"
for tool in sentry-cli op python3 dwarfdump; do
  command -v "$tool" >/dev/null || { echo "Error: $tool not on PATH." >&2; exit 1; }
done
for dsym in "$@"; do
  [[ -d "$dsym/Contents/Resources/DWARF" ]] || { echo "Error: not a dSYM bundle: $dsym" >&2; exit 1; }
done
SENTRY_AUTH_TOKEN="$(op read "$TOKEN_REF" 2>/dev/null)" || { echo "Error: cannot read $TOKEN_REF" >&2; exit 1; }
[[ -n "$SENTRY_AUTH_TOKEN" ]] || { echo "Error: $TOKEN_REF is empty" >&2; exit 1; }
export SENTRY_AUTH_TOKEN SENTRY_ORG SENTRY_PROJECT
trap 'unset SENTRY_AUTH_TOKEN' EXIT

uuids=()
for dsym in "$@"; do
  for dwarf in "$dsym"/Contents/Resources/DWARF/*; do
    sentry-cli debug-files check "$dwarf"
    while read -r uuid; do uuids+=("$uuid"); done < <(dwarfdump --uuid "$dwarf" | awk '{print tolower($2)}')
  done
  sentry-cli debug-files upload --wait "$dsym"
done

python3 - "${uuids[@]}" <<'PY'
import json, os, sys, urllib.parse, urllib.request
org, project, token = os.environ["SENTRY_ORG"], os.environ["SENTRY_PROJECT"], os.environ["SENTRY_AUTH_TOKEN"]
missing = []
for uuid in sys.argv[1:]:
    url = f"https://us.sentry.io/api/0/projects/{org}/{project}/files/dsyms/?query={urllib.parse.quote(uuid)}"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        files = json.load(resp)
    listed = any(f.get("debugId", "").lower().startswith(uuid) for f in files)
    print(f"{'LISTED ' if listed else 'MISSING'} {uuid}")
    if not listed:
        missing.append(uuid)
sys.exit(1 if missing else 0)
PY

sentry-cli releases new "$release"
sentry-cli releases set-commits "$release" --auto || true  # needs the repository integration; non-fatal
sentry-cli releases finalize "$release"
echo "PASS: dSYMs listed and release $release finalized in $SENTRY_ORG/$SENTRY_PROJECT."
