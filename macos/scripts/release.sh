#!/usr/bin/env bash
# Produce a distributable MicroKeys build: signed with a real identity,
# hardened runtime, optionally notarized and stapled, packaged as .dmg and
# .zip with checksums under dist/.
#
#   SIGN_IDENTITY="MicroKeys Dev" make release                  # self-signed
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
#   NOTARY_PROFILE="MicroKeys" make release                     # notarized
#
# NOTARY_PROFILE is the name given to `xcrun notarytool store-credentials`.
# Without it the build is signed but not notarized, which is right for a
# self-signed certificate (Apple will not notarize those).
#
# If a notarization is taking hours (first submissions from a new team can),
# it is safe to Ctrl-C: the submission keeps running at Apple. Pick it up
# later without rebuilding, using the id notarytool printed:
#
#   NOTARY_RESUME=<submission-id> NOTARY_PROFILE="MicroKeys" \
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" make release
set -euo pipefail
cd "$(dirname "$0")/.."

: "${SIGN_IDENTITY:?SIGN_IDENTITY is required for a release (a self-signed or Developer ID certificate name); ad-hoc builds are for local testing only}"
security find-identity -v -p codesigning | grep -q "\"$SIGN_IDENTITY\"" \
    || { echo "no code-signing identity named '$SIGN_IDENTITY' in the keychain" >&2; exit 1; }

VERSION="$(tr -d '[:space:]' < ../VERSION)"
APP="build/MicroKeys.app"
DIST="dist"
STAGE="build/dmg-stage"
DMG="$DIST/MicroKeys-$VERSION.dmg"
ZIP="$DIST/MicroKeys-$VERSION.zip"

if [ -n "${NOTARY_RESUME:-}" ]; then
    # The app in build/ is the one that was submitted; do not rebuild or
    # re-sign it, or the staple would not match the ticket.
    : "${NOTARY_PROFILE:?NOTARY_PROFILE is required with NOTARY_RESUME}"
    [ -d "$APP" ] || { echo "no $APP to staple; the build that was submitted is gone" >&2; exit 1; }
    echo "▸ waiting for notarization $NOTARY_RESUME"
    xcrun notarytool wait "$NOTARY_RESUME" --keychain-profile "$NOTARY_PROFILE"
    xcrun stapler staple "$APP"
    rm -f build/notarize.zip
else
    echo "▸ building v$VERSION"
    SIGN_IDENTITY="$SIGN_IDENTITY" scripts/build-app.sh >/dev/null

    echo "▸ signing with hardened runtime: $SIGN_IDENTITY"
    codesign --force --deep --options runtime --timestamp=none --sign "$SIGN_IDENTITY" "$APP"
    codesign --verify --deep --strict --verbose=1 "$APP"

    if [ -n "${NOTARY_PROFILE:-}" ]; then
        echo "▸ notarizing (profile: $NOTARY_PROFILE)"
        codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
        ditto -c -k --keepParent "$APP" build/notarize.zip
        xcrun notarytool submit build/notarize.zip --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$APP"
        rm -f build/notarize.zip
    fi
fi

echo "▸ packaging"
rm -rf "$STAGE" "$DIST"; mkdir -p "$STAGE" "$DIST"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "MicroKeys $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
ditto -c -k --keepParent "$APP" "$ZIP"
rm -rf "$STAGE"
(cd "$DIST" && shasum -a 256 ./*.dmg ./*.zip > SHA256SUMS.txt)

echo
codesign -dv "$APP" 2>&1 | grep -E "^(Authority|TeamIdentifier)=" | head -2
if [ -n "${NOTARY_PROFILE:-}" ]; then
    spctl --assess --type execute "$APP" && echo "Gatekeeper: accepted"
else
    echo "Gatekeeper: not notarized - recipients must allow it once in System Settings › Privacy & Security, or run: xattr -dr com.apple.quarantine /Applications/MicroKeys.app"
fi
echo
ls -la "$DIST"
