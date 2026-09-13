#!/usr/bin/env bash
# Build MicroKeys.app from the SwiftPM executable. No Xcode needed, only the
# Command Line Tools.
#
#   scripts/build-app.sh                 # ad-hoc signed  -> build/MicroKeys.app
#   SIGN_IDENTITY="MicroKeys Dev" scripts/build-app.sh
#
# Why sign with a real identity: macOS ties the Input Monitoring / Accessibility
# grants to the app's code signature. An ad-hoc signature changes on every
# build, so both grants have to be redone after each rebuild. A self-signed
# certificate (see README) keeps them across builds.
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT=".."                                   # repository root: VERSION, docs/, config.example.json live there
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
IDENTITY="${SIGN_IDENTITY:--}"
OUT="build/MicroKeys.app"

# The app reports the same version as the VERSION file: regenerate the
# checked-in Version.swift so plain `swift build` and this script agree.
GENERATED="Sources/MicroKeys/Version.swift"
printf '// Generated from the repository'"'"'s VERSION file by scripts/build-app.sh.\n// Do not edit by hand; change VERSION and rebuild.\nlet version = "%s"\n' "$VERSION" > "$GENERATED.tmp"
if ! cmp -s "$GENERATED.tmp" "$GENERATED"; then mv "$GENERATED.tmp" "$GENERATED"; echo "▸ updated $GENERATED to $VERSION"; else rm "$GENERATED.tmp"; fi

ARCHS="${ARCHS:---arch arm64 --arch x86_64}"
echo "▸ swift build -c release $ARCHS"
swift build -c release $ARCHS 2>&1 | grep -v "ld: warning: search path" || true
BIN="$(swift build -c release $ARCHS --show-bin-path)/MicroKeys"
[ -x "$BIN" ] || { echo "构建失败：找不到 $BIN" >&2; exit 1; }

echo "▸ assembling $OUT"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN" "$OUT/Contents/MacOS/MicroKeys"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$OUT/Contents/Info.plist"
cp "$ROOT/docs/CONFIG.md" "$ROOT/docs/CONFIG.en.md" "$ROOT/config.example.json" Resources/AppIcon.icns "$OUT/Contents/Resources/"
echo -n "APPL????" > "$OUT/Contents/PkgInfo"

echo "▸ codesign (identity: $IDENTITY)"
codesign --force --deep --sign "$IDENTITY" "$OUT"
codesign --verify --verbose=1 "$OUT"

echo
echo "完成：$OUT  (v$VERSION)"
echo "安装：cp -R $OUT /Applications/   然后 open /Applications/MicroKeys.app"
