#!/usr/bin/env bash
#
# create-signing-cert.sh — create the *stable* self-signed code-signing
# certificate used to sign every MacMetricsView release.
#
# Run this ONCE. The certificate's private key is the thing that must stay
# constant across releases: as long as every build is signed with it, the app's
# designated requirement is
#     identifier "com.pso.MacMetricsView" and certificate leaf = H"<cert hash>"
# which never changes between versions, so the macOS Accessibility (TCC) grant
# survives updates. See scripts/sign-app.sh and TD-010 for the full rationale.
#
# Key custody (mirrors the EdDSA key custody note in TD-009):
#   Losing this certificate/private key means future releases get a *different*
#   leaf hash, which changes the designated requirement and forces every user to
#   re-grant Accessibility one more time. Back up the keychain item securely
#   (Keychain Access -> right-click the identity -> Export) and do NOT commit it.
#
# Usage:
#   scripts/create-signing-cert.sh
#
# This uses openssl + `security import`. The resulting cert is self-signed and
# untrusted; that is fine — codesign signs with it by name and TCC matches on
# the designated requirement regardless of trust. (If you prefer a GUI: Keychain
# Access -> Certificate Assistant -> Create a Certificate, name it exactly
# "Mac Metrics View Self-Signed", Identity Type "Self Signed Root", Certificate
# Type "Code Signing". That path also works and makes the identity show up in
# `security find-identity -v -p codesigning`.)
#
set -euo pipefail

CERT_NAME="${MMV_SIGN_IDENTITY:-Mac Metrics View Self-Signed}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
  echo "A certificate named '$CERT_NAME' already exists in your keychain."
  echo "Its SHA-1 (use as the signing identity if you prefer the hash):"
  security find-certificate -c "$CERT_NAME" -Z 2>/dev/null | sed -n 's/^SHA-1 hash: /  /p'
  echo "Nothing to do. Delete it first if you intend to regenerate (this would"
  echo "force every user to re-grant Accessibility once more)."
  exit 0
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
# A throwaway transport password for the PKCS#12 bundle; the key lands in the
# keychain, not on disk, after import.
p12_pass="$(openssl rand -hex 16)"

echo "Generating self-signed code-signing certificate '$CERT_NAME'..."
openssl req -x509 -newkey rsa:2048 \
  -keyout "$workdir/key.pem" -out "$workdir/cert.pem" \
  -days 3650 -nodes \
  -subj "/CN=$CERT_NAME" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false" >/dev/null 2>&1

openssl pkcs12 -export \
  -inkey "$workdir/key.pem" -in "$workdir/cert.pem" \
  -out "$workdir/cert.p12" -passout "pass:$p12_pass" \
  -name "$CERT_NAME" >/dev/null 2>&1

echo "Importing into login keychain (granting codesign access)..."
security import "$workdir/cert.p12" \
  -k "$KEYCHAIN" -P "$p12_pass" \
  -T /usr/bin/codesign -A >/dev/null

echo ""
echo "Done. Signing identity '$CERT_NAME' is ready."
security find-certificate -c "$CERT_NAME" -Z 2>/dev/null | sed -n 's/^SHA-1 hash: /  SHA-1: /p'
echo ""
echo "Next: build the release app, then run"
echo "  scripts/sign-app.sh <path-to-MacMetricsView.app>"
echo "Back up this identity securely (Keychain Access -> Export) — losing it"
echo "forces all users to re-grant Accessibility once more."
