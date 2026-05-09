#!/usr/bin/env bash
# Build a styled drag-to-Applications .dmg for Snapline.
# Run after ./build.sh has produced build/Snapline.app.
#
# Output: dist/Snapline-<version>.dmg
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Snapline"
APP="build/${APP_NAME}.app"
DIST_DIR="dist"

if [[ ! -d "$APP" ]]; then
    echo "✗ ${APP} not found — run ./build.sh first" >&2
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
    "${APP}/Contents/Info.plist" 2>/dev/null || echo "0.0.0")
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
VOL_NAME="${APP_NAME} ${VERSION}"

mkdir -p "${DIST_DIR}"
rm -f "${DMG_PATH}"

STAGE=$(mktemp -d)
RW_DMG=$(mktemp -d)/_rw.dmg
trap 'detach_if_mounted; rm -rf "$STAGE" "$(dirname "$RW_DMG")"' EXIT

MOUNT_DIR=""
detach_if_mounted() {
    [[ -n "${MOUNT_DIR:-}" && -d "$MOUNT_DIR" ]] || return 0
    hdiutil detach "$MOUNT_DIR" -quiet -force >/dev/null 2>&1 || true
}

echo "→ Rendering DMG background image…"
mkdir -p "$STAGE/.background"
swift installer/render-background.swift "$STAGE/.background/background.png" >/dev/null

echo "→ Staging ${APP_NAME}.app + Applications symlink…"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# Calculate a comfortably-oversized staging DMG. App size + 64 MB headroom.
APP_KB=$(du -sk "$APP" | awk '{print $1}')
DMG_SIZE_MB=$(( APP_KB / 1024 + 64 ))
[[ $DMG_SIZE_MB -lt 96 ]] && DMG_SIZE_MB=96

echo "→ Creating staging DMG (${DMG_SIZE_MB} MB, APFS)…"
hdiutil create \
    -volname "$VOL_NAME" \
    -srcfolder "$STAGE" \
    -size "${DMG_SIZE_MB}m" \
    -fs APFS \
    -format UDRW \
    -ov \
    "$RW_DMG" >/dev/null

echo "→ Detaching any stale '${VOL_NAME}' mounts…"
for m in "/Volumes/${VOL_NAME}"*; do
    [[ -d "$m" ]] && hdiutil detach "$m" -force -quiet 2>/dev/null || true
done

echo "→ Mounting staging DMG to apply window layout…"
# Let hdiutil mount under /Volumes/$VOL_NAME — that's where Finder looks.
# -noautoopen keeps Finder from popping the window in our face mid-build.
hdiutil attach "$RW_DMG" -noautoopen >/dev/null
MOUNT_DIR="/Volumes/${VOL_NAME}"

# Best-effort window layout. If the script can't drive Finder (no GUI session,
# or Automation permission denied) we ship the DMG without cosmetic layout
# rather than failing the build.
APPLESCRIPT_ERR=$(osascript 2>&1 <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 800, 520}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set text size of viewOptions to 12
        set background picture of viewOptions to file ".background:background.png"
        set position of item "${APP_NAME}.app" of container window to {160, 200}
        set position of item "Applications" of container window to {440, 200}
        update without registering applications
        delay 1.5
        close
    end tell
end tell
APPLESCRIPT
) || true
if [[ -n "$APPLESCRIPT_ERR" ]]; then
    echo "  ⚠ osascript said: $APPLESCRIPT_ERR"
fi

sync
detach_if_mounted
MOUNT_DIR=""

echo "→ Compressing to final DMG…"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null

# If the .app was signed with a stable identity, sign the DMG with the same one.
CERT_NAME="Snapline Self-Signed"
CERT_HASH=$(security find-certificate -c "$CERT_NAME" -Z 2>/dev/null \
    | awk '/SHA-1 hash/ {print $NF; exit}' || true)
if [[ -n "${CERT_HASH:-}" ]]; then
    echo "→ Signing DMG with '$CERT_NAME'…"
    codesign --force --sign "$CERT_HASH" "$DMG_PATH"
fi

SIZE=$(du -h "$DMG_PATH" | cut -f1)
echo "✓ Built ${DMG_PATH} (${SIZE})"
