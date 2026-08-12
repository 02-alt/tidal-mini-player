#!/bin/bash
# Builds "Tidal Mini Player.app" from the Swift sources — no Xcode required.
# Also compiles the vendored MediaRemoteAdapter.framework (BSD-3, see
# ThirdParty/mediaremote-adapter/LICENSE) and bundles it with the perl loader.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Tidal Mini Player"
EXECUTABLE="TidalMiniPlayer"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
MACOS_MIN="13.0"
# Universal build: runs natively on both Apple silicon and Intel Macs.
ARCHS=(arm64 x86_64)
CLANG_ARCH_FLAGS=(); for a in "${ARCHS[@]}"; do CLANG_ARCH_FLAGS+=(-arch "$a"); done

ADAPTER_SRC="ThirdParty/mediaremote-adapter"
RES="$APP/Contents/Resources"

# Code signing. Preference order:
#   1. Developer ID Application — notarizable, trusted on any Mac, and a stable
#      identity so the Accessibility grant persists for everyone (+ Hardened
#      Runtime & secure timestamp, both required by the notary service).
#   2. Local self-signed identity — stable across rebuilds but not notarizable
#      (see docs/local-signing.md).
#   3. Ad-hoc — last resort; Accessibility grant won't survive rebuilds.
DEV_ID=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -m1 "Developer ID Application" | sed -E 's/^[^"]*"([^"]+)".*$/\1/')
LOCAL_ID="Tidal Mini Player Local Signing"
if [ -n "$DEV_ID" ]; then
    CODESIGN=(codesign --force --options runtime --timestamp --sign "$DEV_ID")
    echo "› Signing with Developer ID: $DEV_ID"
elif security find-identity -p codesigning 2>/dev/null | grep -q "$LOCAL_ID"; then
    CODESIGN=(codesign --force --timestamp=none --sign "$LOCAL_ID")
    echo "› Signing with local identity: $LOCAL_ID (not notarizable)"
else
    CODESIGN=(codesign --force --sign -)
    echo "› Signing ad-hoc (Accessibility grant won't persist across rebuilds)"
fi

echo "› Cleaning…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$RES"

echo "› Building MediaRemoteAdapter.framework…"
FW="$RES/MediaRemoteAdapter.framework"
mkdir -p "$FW/Versions/A/Resources"
# All adapter sources except test.m (the optional "test" command, which needs
# the separate test client we don't bundle).
ADAPTER_M=$(find "$ADAPTER_SRC/src" -name '*.m' ! -name 'test.m' ! -path '*/test/*')
clang -dynamiclib -fobjc-arc -fvisibility=default -O2 \
    "${CLANG_ARCH_FLAGS[@]}" -mmacosx-version-min="$MACOS_MIN" \
    -I"$ADAPTER_SRC/include" -I"$ADAPTER_SRC/src" \
    -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
    -install_name @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter \
    $ADAPTER_M \
    -o "$FW/Versions/A/MediaRemoteAdapter"

cat > "$FW/Versions/A/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MediaRemoteAdapter</string>
<key>CFBundleIdentifier</key><string>com.vandenbe.MediaRemoteAdapter</string>
<key>CFBundleName</key><string>MediaRemoteAdapter</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>CFBundleVersion</key><string>0.1.0</string>
</dict></plist>
PLIST
ln -sf A "$FW/Versions/Current"
ln -sf Versions/Current/MediaRemoteAdapter "$FW/MediaRemoteAdapter"
ln -sf Versions/Current/Resources "$FW/Resources"
"${CODESIGN[@]}" "$FW" >/dev/null 2>&1 || true

echo "› Bundling adapter loader…"
cp "$ADAPTER_SRC/mediaremote-adapter.pl" "$RES/mediaremote-adapter.pl"
cp "$ADAPTER_SRC/LICENSE" "$RES/MediaRemoteAdapter.LICENSE"

echo "› Compiling Swift sources (universal: ${ARCHS[*]})…"
# swiftc builds one arch at a time; compile each slice, then lipo them together.
SWIFT_SLICES=()
for a in "${ARCHS[@]}"; do
    slice="$BUILD_DIR/$EXECUTABLE-$a"
    swiftc -O \
        -target "$a-apple-macos$MACOS_MIN" \
        -framework SwiftUI -framework AppKit -framework ServiceManagement \
        -o "$slice" \
        Sources/*.swift
    SWIFT_SLICES+=("$slice")
done
lipo -create "${SWIFT_SLICES[@]}" -o "$APP/Contents/MacOS/$EXECUTABLE"
rm -f "${SWIFT_SLICES[@]}"

echo "› Assembling bundle…"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$RES/AppIcon.icns"
cp Resources/IdleMark.png "$RES/IdleMark.png"

echo "› Code signing…"
"${CODESIGN[@]}" "$APP/Contents/MacOS/$EXECUTABLE" >/dev/null 2>&1 || true
"${CODESIGN[@]}" "$APP" >/dev/null 2>&1 || \
    echo "  (codesign skipped — app will still run)"

echo "✓ Built: $APP"
echo "  Launch with:  open \"$APP\""
