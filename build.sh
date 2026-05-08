#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Snapline"
BUILD_DIR=".build/release"
APP_DIR="build/${APP_NAME}.app"
CERT_NAME="Snapline Self-Signed"

echo "→ Building Swift package (release)…"
swift build -c release

echo "→ Assembling ${APP_NAME}.app bundle…"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${APP_DIR}/Contents/Info.plist"
printf 'APPL????' > "${APP_DIR}/Contents/PkgInfo"

# --- App icon: PNG → .icns ---------------------------------------------------
if [[ -f "Resources/AppIcon.png" ]]; then
    echo "→ Generating AppIcon.icns from Resources/AppIcon.png…"
    ICONSET=$(mktemp -d)/AppIcon.iconset
    mkdir -p "$ICONSET"
    SRC="Resources/AppIcon.png"
    sips -z 16 16     "$SRC" --out "$ICONSET/icon_16x16.png"      >/dev/null
    sips -z 32 32     "$SRC" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
    sips -z 32 32     "$SRC" --out "$ICONSET/icon_32x32.png"      >/dev/null
    sips -z 64 64     "$SRC" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
    sips -z 128 128   "$SRC" --out "$ICONSET/icon_128x128.png"    >/dev/null
    sips -z 256 256   "$SRC" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   "$SRC" --out "$ICONSET/icon_256x256.png"    >/dev/null
    sips -z 512 512   "$SRC" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
    sips -z 512 512   "$SRC" --out "$ICONSET/icon_512x512.png"    >/dev/null
    sips -z 1024 1024 "$SRC" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
    iconutil -c icns "$ICONSET" -o "${APP_DIR}/Contents/Resources/AppIcon.icns"
    # Also copy the source PNG so the onboarding window can show it
    cp "$SRC" "${APP_DIR}/Contents/Resources/AppIcon.png"
    rm -rf "$(dirname "$ICONSET")"
fi

# --- Code signing -----------------------------------------------------------
CERT_HASH=$(security find-certificate -c "$CERT_NAME" -Z 2>/dev/null \
    | awk '/SHA-1 hash/ {print $NF; exit}')

if [[ -n "${CERT_HASH:-}" ]]; then
    echo "→ Signing with stable identity '$CERT_NAME' (SHA-1 ${CERT_HASH:0:12}…)"
    codesign --force --deep --sign "$CERT_HASH" "${APP_DIR}"
else
    echo "→ Signing ad-hoc — run ./create-cert.sh once for stable TCC permissions"
    codesign --force --deep --sign - "${APP_DIR}"
fi

echo "✓ Built ${APP_DIR}"
