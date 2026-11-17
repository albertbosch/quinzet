#!/bin/bash
# Compila Quinzet i genera Quinzet.dmg (cal Xcode).
set -euo pipefail
cd "$(dirname "$0")"

APP="Quinzet"
OUT="build"

# Amb el SDK de macOS 27, @State és una macro que només porta Xcode.
# Si no hi ha Xcode, es compila amb les Command Line Tools i un SDK anterior (26.x).
SDK_ARGS=()
XCODE="$(ls -d /Applications/Xcode*.app 2>/dev/null | sort | tail -1 || true)"
if [ -z "${DEVELOPER_DIR:-}" ] && [ -n "$XCODE" ]; then
  export DEVELOPER_DIR="$XCODE/Contents/Developer"
  TOOL="$DEVELOPER_DIR"
else
  SDK="$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | sort -V | tail -1 || true)"
  if [ -z "$SDK" ]; then
    echo "✗ Cal Xcode (App Store) o un SDK de macOS 26 a les Command Line Tools."; exit 1
  fi
  export SDKROOT="$SDK"
  SDK_ARGS=(--sdk "$SDK")
  TOOL="$SDK"
fi
echo "▸ Fent servir: $TOOL"
if [ -d .build ] && [ "$(cat .build/.toolchain 2>/dev/null || true)" != "$TOOL" ]; then rm -rf .build; fi
mkdir -p .build && echo "$TOOL" > .build/.toolchain

echo "▸ Compilant…"
swift build -c release ${SDK_ARGS[@]+"${SDK_ARGS[@]}"}
BIN="$(swift build -c release ${SDK_ARGS[@]+"${SDK_ARGS[@]}"} --show-bin-path)/$APP"

echo "▸ Muntant $APP.app…"
rm -rf "$OUT"
mkdir -p "$OUT/$APP.app/Contents/MacOS" "$OUT/$APP.app/Contents/Resources"
cp "$BIN" "$OUT/$APP.app/Contents/MacOS/$APP"
cp Resources/Info.plist "$OUT/$APP.app/Contents/Info.plist"
cp Resources/AppIcon.icns "$OUT/$APP.app/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$OUT/$APP.app"

echo "▸ Creant $APP.dmg…"
mkdir -p "$OUT/dmg"
cp -R "$OUT/$APP.app" "$OUT/dmg/"
ln -s /Applications "$OUT/dmg/Applications"
rm -f "$APP.dmg"
hdiutil create -volname "$APP" -srcfolder "$OUT/dmg" -ov -format UDZO "$APP.dmg" >/dev/null

echo "✓ Fet: $(pwd)/$APP.dmg"
open "$APP.dmg"
