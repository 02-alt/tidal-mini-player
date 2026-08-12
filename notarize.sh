#!/bin/bash
# Notarizes the built app with Apple, staples the ticket, and produces a
# notarized DMG that launches cleanly (no Gatekeeper warning) on any Mac.
#
# Prereqs (one time):
#   • ./build.sh has run and signed with a Developer ID (see build.sh).
#   • Notary credentials stored in the keychain under the profile below:
#       xcrun notarytool store-credentials "tidal-notary" \
#         --apple-id "<you@example.com>" --team-id "<TEAMID>"
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Tidal Mini Player.app"
PROFILE="tidal-notary"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")

# Bail early if the app isn't Developer ID signed (notary will reject ad-hoc).
# (Capture first — `... | grep -q` under `set -o pipefail` trips on SIGPIPE.)
SIGN_INFO=$(codesign -dv --verbose=2 "$APP" 2>&1 || true)
if ! grep -q "Developer ID Application" <<<"$SIGN_INFO"; then
    echo "✗ $APP is not signed with a Developer ID — run ./build.sh with the cert installed first." >&2
    exit 1
fi

echo "› Zipping for submission…"
ZIP="build/TidalMiniPlayer-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "› Submitting to Apple notary service (this can take a few minutes)…"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "› Stapling the ticket to the app…"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "› Building notarized DMG…"
DEST="dist/Tidal Mini Player $VERSION.dmg"
mkdir -p dist
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
[ -f dist/INSTALL.txt ] && cp dist/INSTALL.txt "$STAGE/INSTALL.txt"
ln -s /Applications "$STAGE/Applications"
rm -f "$DEST"
hdiutil create -quiet -volname "Tidal Mini Player" -srcfolder "$STAGE" -ov -format UDZO "$DEST"
rm -rf "$STAGE"

echo "› Notarizing the DMG itself…"
xcrun notarytool submit "$DEST" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DEST"
xcrun stapler validate "$DEST"

rm -f "$ZIP"
echo "✓ Notarized & stapled: $DEST"
echo "  Verify Gatekeeper:  spctl -a -vvv \"$APP\""
