#!/bin/bash
# Creates a stable, self-signed code-signing identity used to sign CodexSwitcher.
# A stable identity keeps Keychain entries readable across rebuilds (ad-hoc
# signatures change every build, which orphans previously saved API keys).
#
# Requires: openssl (available on macOS), security (built-in).
set -euo pipefail

CERT_NAME="CodexSwitcher Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
  echo "Signing identity '$CERT_NAME' already exists."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Self-signed cert that macOS accepts for code signing: CA:TRUE so it can be
# marked trusted, plus the codeSigning extended key usage.
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -subj "/CN=$CERT_NAME/O=CodexSwitcher/C=US" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,digitalSignature,keyCertSign" \
  -addext "extendedKeyUsage=codeSigning" >/dev/null 2>&1

openssl pkcs12 -export -legacy -out "$TMP/identity.p12" \
  -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -passout pass:csdev123 >/dev/null 2>&1

security import "$TMP/identity.p12" \
  -k "$KEYCHAIN" -P csdev123 -T /usr/bin/codesign -T /usr/bin/security >/dev/null

security add-trusted-cert -d -r trustRoot -k "$KEYCHAIN" "$TMP/cert.pem" >/dev/null 2>&1 || true

echo "Created signing identity '$CERT_NAME' in your login keychain."
echo "Rebuild with ./build.sh to start signing with it."
