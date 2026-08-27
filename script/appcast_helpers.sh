#!/usr/bin/env bash

normalize_appcast_build() {
  local value="$1"
  value="${value#"${value%%[!0]*}"}"
  printf '%s\n' "${value:-0}"
}

is_newer_appcast_build() {
  local incoming current
  incoming="$(normalize_appcast_build "$1")"
  current="$(normalize_appcast_build "$2")"
  if [[ ${#incoming} -ne ${#current} ]]; then
    [[ ${#incoming} -gt ${#current} ]]
    return
  fi
  [[ "$incoming" > "$current" ]]
}

current_appcast_build() {
  local appcast_path="$1"
  /usr/bin/xmllint \
    --xpath 'string((//*[local-name()="item"]/*[local-name()="version"])[1])' \
    "$appcast_path"
}

escape_cdata() {
  local value="$1"
  printf '%s\n' "${value//]]>/]]]]><![CDATA[>}"
}
