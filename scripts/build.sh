#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

PRODUCT="Framegentic"
APP=".build/$PRODUCT.app"
VERSION="${VERSION:-0.0.0-dev}"
BUILD_NUM="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

# Ad-hoc signatures change cdhash every build, which resets the TCC permission
# grants. Prefer a stable identity whenever one is available; override with
# SIGN_IDENTITY (e.g. "Developer ID Application" for releases).
if [ -z "${SIGN_IDENTITY:-}" ]; then
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then
        SIGN_IDENTITY="Apple Development"
    else
        SIGN_IDENTITY="-"
    fi
fi

echo "Building $PRODUCT $VERSION ($BUILD_NUM)…"
swift build -c release

echo "Bundling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/$PRODUCT" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns Resources/MenuBarIcon.png Resources/MenuBarIcon@2x.png "$APP/Contents/Resources/"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUM" "$APP/Contents/Info.plist"

echo "Signing ($SIGN_IDENTITY)…"
if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP"
else
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"

echo ""
echo "Done → $APP"
echo "Run:     open $APP"
echo "Install: rm -rf /Applications/$PRODUCT.app && cp -R $APP /Applications/"
