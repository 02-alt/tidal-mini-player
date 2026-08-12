#!/bin/bash
# Cuts a release: zips the notarized app, generates the Sparkle appcast (signed
# with the EdDSA key in your keychain), publishes a GitHub Release with the zip
# + DMG, and pushes the updated appcast.xml so existing installs auto-update.
#
# Before running: bump CFBundleShortVersionString AND CFBundleVersion in
# Resources/Info.plist, then:   ./build.sh && ./notarize.sh && ./release.sh
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Tidal Mini Player.app"
REPO="02-alt/tidal-mini-player"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
TAG="v$VERSION"

# The app must be notarized + stapled (so the update itself passes Gatekeeper).
if ! xcrun stapler validate "$APP" >/dev/null 2>&1; then
    echo "✗ $APP isn't notarized/stapled. Run ./build.sh && ./notarize.sh first." >&2
    exit 1
fi

echo "› Zipping update archive…"
mkdir -p releases
ZIP="releases/TidalMiniPlayer-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "› Generating signed appcast…"
ThirdParty/Sparkle/bin/generate_appcast releases \
    --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/"
cp releases/appcast.xml appcast.xml

echo "› Publishing GitHub Release $TAG…"
DMG="dist/Tidal Mini Player $VERSION.dmg"
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    gh release upload "$TAG" "$ZIP" "$DMG" --repo "$REPO" --clobber
else
    gh release create "$TAG" "$ZIP" "$DMG" --repo "$REPO" \
        --title "Tidal Mini Player $VERSION" --notes "Release $TAG."
fi

echo "› Pushing appcast…"
git add appcast.xml
git commit -q -m "Release $TAG" || true
git push -q origin HEAD:main

echo "✓ Released $TAG — existing installs will offer the update."
