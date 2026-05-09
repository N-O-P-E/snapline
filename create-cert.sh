#!/usr/bin/env bash
# One-time setup: creates a self-signed code-signing certificate in your login
# keychain so every Snapline rebuild signs with the same identity. macOS TCC
# (Accessibility, Screen Recording, etc.) then keeps your grants across rebuilds.

set -euo pipefail

CERT_NAME="Snapline Self-Signed"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "✓ Code-signing identity '$CERT_NAME' already exists."
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/req.conf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = v3_req

[dn]
CN = $CERT_NAME

[v3_req]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

echo "→ Generating self-signed code-signing certificate…"
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -config "$TMP/req.conf" 2>/dev/null

P12_PASS="snapline"
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$CERT_NAME" -out "$TMP/cert.p12" -passout "pass:$P12_PASS" 2>/dev/null

echo "→ Importing into login keychain (may prompt for keychain password)…"
security import "$TMP/cert.p12" -P "$P12_PASS" \
    -T /usr/bin/codesign \
    -k "$HOME/Library/Keychains/login.keychain-db"

echo
echo "✓ Created '$CERT_NAME' in your login keychain."
echo "  Subsequent rebuilds will sign stably; TCC permissions will stick."
echo
echo "Next: ./build.sh && open build/Snapline.app"
