#!/usr/bin/env bash
#
# capture-popovers.sh — fully-automated capture of the 4 popover-demo screenshots
# (CPU / RAM / Network+Disk / Tokens) in both light and dark, straight from the real
# built app. Replaces the manual popover steps in capture-site-screenshots.sh.
#
# How it works
# ------------
# The app has a dev-only capture mode (env MMV_CAPTURE=1, inert otherwise): it runs as
# a regular app, opens the popover with the card(s) named in MMV_CAPTURE_CARD expanded,
# suppresses transient banners, and prints the popover's window id to stderr. This script
# launches it once per (theme, tab), grabs exactly that window with `screencapture -l`
# (z-order–independent), and writes the manifest-named PNGs into docs/assets/.
#
# The images are real macOS popover windows: fixed width, per-tab height, native shadow
# and rounded corners baked in (transparent margins). Validate with check-site-assets.mjs.
#
# Re-run per release to keep the demo in sync with the shipped popover.
# Requirements: Screen Recording permission for the terminal, and Automation permission
# for System Events (used to toggle appearance).
set -euo pipefail

cd "$(dirname "$0")/.."
ASSETS="docs/assets"
DERIVED="build/capture"
SCHEME="MacMetricsView"

echo "==> Building $SCHEME (Release)…"
xcodebuild -project MacMetricsView.xcodeproj -scheme "$SCHEME" \
  -configuration Release -derivedDataPath "$DERIVED" build 1>/dev/null
BIN="$DERIVED/Build/Products/Release/MacMetricsView.app/Contents/MacOS/MacMetricsView"
test -x "$BIN" || { echo "error: built binary not found"; exit 1; }

ERR="$(mktemp)"
trap 'killall MacMetricsView 2>/dev/null || true; rm -f "$ERR"' EXIT

# tab id (manifest) -> MMV_CAPTURE_CARD value (comma-separated card kinds to expand)
grab() { # $1 theme  $2 cards  $3 outfile
  killall MacMetricsView 2>/dev/null || true; sleep 1
  MMV_CAPTURE=1 MMV_CAPTURE_CARD="$2" "$BIN" 2>"$ERR" >/dev/null &
  sleep 4
  local win
  win="$(grep -o 'MMV_POPOVER_WINDOW=[0-9]*' "$ERR" | head -1 | cut -d= -f2)"
  [ -n "$win" ] || { echo "  !! no popover window id for $3"; return 1; }
  screencapture -o -x -l "$win" "$ASSETS/$3"
  echo "  $3  ->  $(sips -g pixelWidth -g pixelHeight "$ASSETS/$3" | tail -2 | awk '{print $2}' | paste -sd x -)"
}

set_appearance() { # $1 = true|false (dark mode on/off)
  osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $1"
  sleep 1
}

for theme in dark light; do
  [ "$theme" = dark ] && set_appearance true || set_appearance false
  echo "== $theme =="
  grab "$theme" "cpu"          "popover-cpu-$theme.png"
  grab "$theme" "ram"          "popover-ram-$theme.png"
  grab "$theme" "network,disk" "popover-netdisk-$theme.png"
  grab "$theme" "tokens"       "popover-ai-$theme.png"
done

echo "==> Done. Validate with: node scripts/check-site-assets.mjs"
