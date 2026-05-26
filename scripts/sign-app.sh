#!/usr/bin/env bash
#
# sign-app.sh — re-sign a built MacMetricsView.app with a *stable* code-signing
# identity so the macOS Accessibility (TCC) grant survives version updates.
#
# Why this exists
# ---------------
# The app ships ad-hoc signed (no Apple Developer ID). With ad-hoc signing the
# code's "designated requirement" is the binary's cdhash, which changes on every
# build/version. TCC keys the Accessibility grant to that requirement, so each
# update silently invalidates the grant (System Settings still shows the stale
# entry ON, but `AXIsProcessTrusted()` returns false). See TD-010 and
# docs/ai/plans/plan-accessibility-permission-persistence.md.
#
# Signing every release with the *same* self-signed certificate changes the
# designated requirement to:
#     identifier "com.pso.MacMetricsView" and certificate leaf = H"<cert hash>"
# which is constant across versions. TCC then preserves the grant across manual
# installs and Sparkle updates. (Gatekeeper first-launch friction is unchanged;
# notarization is the separate, deferred fix in TD-010 / backlog item B1.)
#
# Create the certificate once with scripts/create-signing-cert.sh.
#
# Usage
# -----
#   scripts/sign-app.sh <path-to-MacMetricsView.app> [identity]
#
# `identity` is the certificate's common name or SHA-1 hash as listed by
#   security find-identity -v
# It defaults to the MMV_SIGN_IDENTITY environment variable, then to the
# certificate name created by create-signing-cert.sh.
#
set -euo pipefail

APP="${1:-}"
IDENTITY="${2:-${MMV_SIGN_IDENTITY:-Mac Metrics View Self-Signed}}"

if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "error: pass the path to MacMetricsView.app as the first argument" >&2
  echo "usage: scripts/sign-app.sh <path-to-MacMetricsView.app> [identity]" >&2
  exit 2
fi

# codesign accepts an identity by common name or by SHA-1 hash. A self-signed,
# untrusted cert does NOT appear in `find-identity -v` (which filters to
# trust-valid identities), yet codesign signs with it fine and TCC matches on
# the resulting designated requirement regardless of trust. So confirm the
# certificate simply *exists* in a keychain, by name or by hash.
identity_exists() {
  security find-certificate -c "$IDENTITY" >/dev/null 2>&1 && return 0
  security find-identity -v 2>/dev/null | grep -Fq "$IDENTITY" && return 0
  security find-certificate -a -Z 2>/dev/null | grep -Fiq "$IDENTITY"
}
if ! identity_exists; then
  echo "error: signing identity '$IDENTITY' not found in any keychain." >&2
  echo "       create it once with scripts/create-signing-cert.sh, or pass the" >&2
  echo "       correct name/hash as the second argument." >&2
  exit 1
fi

sign() {
  local target="$1"
  codesign --force --timestamp=none --sign "$IDENTITY" "$target"
  echo "  signed: ${target#"$APP"/}"
}

echo "Signing $APP with identity: $IDENTITY"
echo "(nested code first, main bundle last)"

# 1. Nested code inside each embedded framework, deepest first: XPC services,
#    helper tools, and helper apps must be signed before the framework that
#    contains them, which must be signed before the outer app.
while IFS= read -r -d '' fw; do
  # XPC services (Sparkle's Downloader.xpc / Installer.xpc).
  while IFS= read -r -d '' xpc; do sign "$xpc"; done \
    < <(find "$fw" -type d -name "*.xpc" -print0)

  # Helper apps (Sparkle's Updater.app).
  while IFS= read -r -d '' nested; do sign "$nested"; done \
    < <(find "$fw" -type d -name "*.app" -print0)

  # Standalone helper executables (Sparkle's Autoupdate). Match Mach-O files
  # that are not the framework's own versioned dylib symlink target.
  while IFS= read -r -d '' bin; do
    if file -b "$bin" 2>/dev/null | grep -q "Mach-O"; then sign "$bin"; fi
  done < <(find "$fw" -type f -perm -u+x -print0)

  # The framework itself.
  sign "$fw"
done < <(find "$APP/Contents/Frameworks" -type d -name "*.framework" -print0 2>/dev/null)

# 2. The outer app last.
sign "$APP"

echo ""
echo "Verifying..."
codesign --verify --deep --strict --verbose=2 "$APP"

echo ""
echo "Designated requirement (must be identifier + certificate leaf, NOT cdhash):"
codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => /  /p'
