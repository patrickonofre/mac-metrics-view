#!/usr/bin/env bash
#
# capture-site-screenshots.sh — semi-automated capture of the fresh 2.0 marketing
# screenshots the redesigned site depends on (task_01 of site-redesign-2.0).
#
# Why this is semi-automated
# --------------------------
# The app ships as an LSUIElement menu-bar app with no built-in "auto-open
# popover" hook, so a fully headless capture isn't possible. This script builds
# the 2.0 .app and launches it; the operator then opens the popover, switches to
# each tab in the requested appearance, and the script captures + optimizes each
# region into docs/assets/ with the canonical names from site-assets-manifest.json.
#
# Target names + dimensions are the contract checked by scripts/check-site-assets.mjs.
#
# Procedure
# ---------
#   1. Set realistic sample data (run a few CPU tasks, have token logs present)
#      so the popover shows credible, non-zero values.
#   2. Run this script. It builds + launches the app.
#   3. For each prompt, switch macOS appearance (System Settings > Appearance, or
#      `osascript` toggle below), open the popover, select the named tab, then
#      click the target window when screencapture's camera cursor appears.
#   4. The script optimizes each capture to the manifest size with `sips`.
#
# Re-run per release to keep the demo in sync with the shipped popover (ADR-003).
set -euo pipefail

cd "$(dirname "$0")/.."
ASSETS="docs/assets"
SCHEME="MacMetricsView"

echo "==> Building 2.0 .app (Release)…"
xcodebuild -project MacMetricsView.xcodeproj -scheme "$SCHEME" \
  -configuration Release -derivedDataPath build/capture build 1>/dev/null
APP="$(find build/capture -maxdepth 5 -name 'MacMetricsView.app' -type d | head -1)"
[ -n "$APP" ] || { echo "error: built .app not found"; exit 1; }
echo "    built: $APP"
test -x "$APP/Contents/MacOS/MacMetricsView" || { echo "error: no executable in bundle"; exit 1; }

open "$APP"
echo "==> App launched. Open the popover and follow each prompt."

# tab id -> human label (must match manifest tab ids)
TABS=("cpu:CPU (top processes)" \
      "ram:RAM (breakdown/swap/kernel)" \
      "netdisk:Network/Disk (detail + totals)" \
      "ai:AI tokens (burn/cost/projection)")

capture() {  # $1 outfile  $2 prompt
  echo ""
  read -r -p "    Ready to capture $2 — press Enter, then click the popover window… " _
  screencapture -i -o "$ASSETS/$1"          # interactive window/region capture
  [ -f "$ASSETS/$1" ] || { echo "    (skipped $1)"; return; }
  # Normalize to the manifest's logical width (height auto), keeping it crisp.
  sips --resampleWidth 680 "$ASSETS/$1" 1>/dev/null
  echo "    saved + sized: $ASSETS/$1"
}

echo ""
echo "### MENU BAR STRIP"
read -r -p "    Ready to capture the menu-bar strip — press Enter, then drag-select it… " _
screencapture -i -o "$ASSETS/menu-bar-2.0.png"
[ -f "$ASSETS/menu-bar-2.0.png" ] && sips --resampleWidth 744 "$ASSETS/menu-bar-2.0.png" 1>/dev/null || true

for theme in light dark; do
  echo ""
  echo "### Set macOS appearance to: $theme, then capture each tab"
  for entry in "${TABS[@]}"; do
    id="${entry%%:*}"; label="${entry#*:}"
    capture "popover-${id}-${theme}.png" "$label [$theme]"
  done
done

echo ""
echo "==> Done. Validate with: node scripts/check-site-assets.mjs"
