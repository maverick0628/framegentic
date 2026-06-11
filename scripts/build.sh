#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

PRODUCT="ClaudeShot"
APP="$PRODUCT.app"

echo "Building $PRODUCT…"
swift build -c release 2>&1

echo "Bundling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp ".build/release/$PRODUCT" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp Resources/MenuBarIcon.png "$APP/Contents/Resources/"
cp Resources/MenuBarIcon@2x.png "$APP/Contents/Resources/"

echo "Signing (ad-hoc)…"
codesign --force --deep --sign - "$APP"

echo ""
echo "Done → $APP"
echo "Run:     open $APP"
echo "Install: cp -R $APP /Applications/"
