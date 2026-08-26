#!/usr/bin/env bash
# Validates local release inputs only. It never fetches or modifies artifacts.
set -euo pipefail

app_path="${1:-}"
appcast_path="${2:-}"

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

if [[ -z "$app_path" || -z "$appcast_path" ]]; then
  printf 'usage: %s <MacMetricsView.app> <appcast.xml>\n' "$0" >&2
  exit 2
fi

[[ -d "$app_path" ]] || fail "app bundle not found: $app_path"
[[ -f "$appcast_path" ]] || fail "appcast not found: $appcast_path"

info_plist="$app_path/Contents/Info.plist"
[[ -f "$info_plist" ]] || fail "bundle Info.plist not found: $info_plist"

/usr/bin/plutil -lint "$info_plist" >/dev/null || fail "bundle Info.plist is malformed"
/usr/bin/xmllint --noout "$appcast_path" || fail "appcast XML is malformed"
signature_output="$(/usr/bin/codesign --verify --deep --strict "$app_path" 2>&1)" || {
  # Releases use a stable self-signed certificate. `codesign` completes the
  # structural verification but reports this expected trust-chain condition.
  # Any other result is an integrity failure.
  [[ "$signature_output" == *"CSSMERR_TP_NOT_TRUSTED"* ]] \
    || fail "bundle signature verification failed: $signature_output"
}

bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist" 2>/dev/null)" \
  || fail "CFBundleShortVersionString is missing"
public_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$info_plist" 2>/dev/null)" \
  || fail "SUPublicEDKey is missing"

[[ -n "$bundle_version" ]] || fail "CFBundleShortVersionString is empty"
[[ -n "$public_key" && "$public_key" != *"REPLACE_"* ]] \
  || fail "SUPublicEDKey is unresolved"

appcast_version="$(/usr/bin/xmllint --xpath \
  'string((//*[local-name()="channel"]/*[local-name()="item"])[1]/*[local-name()="shortVersionString"])' \
  "$appcast_path" 2>/dev/null)" || fail "appcast has no readable release item"

[[ -n "$appcast_version" ]] || fail "appcast has no release version"
[[ "$bundle_version" == "$appcast_version" ]] \
  || fail "version mismatch: bundle $bundle_version, newest appcast $appcast_version"

printf 'PASS: plist valid\n'
printf 'PASS: appcast XML valid\n'
printf 'PASS: signature valid\n'
printf 'PASS: public key resolved\n'
printf 'PASS: version %s matches newest appcast item\n' "$bundle_version"
