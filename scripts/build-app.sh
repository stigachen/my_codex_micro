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

VERSION="${VERSION:-$(sed -n 's/^let version = "\(.*\)"/\1/p' Sources/MicroKeys/main.swift)}"
IDENTITY="${SIGN_IDENTITY:--}"
OUT="build/MicroKeys.app"

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
cp docs/CONFIG.md docs/CONFIG.en.md config.example.json Resources/AppIcon.icns "$OUT/Contents/Resources/"
echo -n "APPL????" > "$OUT/Contents/PkgInfo"

echo "▸ codesign (identity: $IDENTITY)"
codesign --force --deep --sign "$IDENTITY" "$OUT"
codesign --verify --verbose=1 "$OUT"

echo
echo "完成：$OUT  (v$VERSION)"
echo "安装：cp -R $OUT /Applications/   然后 open /Applications/MicroKeys.app"
