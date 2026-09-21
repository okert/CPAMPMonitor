#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
BUILD_ARCH="${APP_ARCH:-$(uname -m)}"
case "$BUILD_ARCH" in
    arm64|x86_64)
        ;;
    *)
        print -u2 "Unsupported APP_ARCH: $BUILD_ARCH (expected arm64 or x86_64)"
        exit 2
        ;;
esac

swift build -c release --arch "$BUILD_ARCH" --product CPAMPMonitor
OUTPUT_DIR="${1:-$PWD/dist}"
mkdir -p "$OUTPUT_DIR"
APP="$OUTPUT_DIR/CPAMP Monitor.app"
ICONSET="$OUTPUT_DIR/AppIcon.iconset"
rm -rf "$APP" "$ICONSET"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/${BUILD_ARCH}-apple-macosx/release/CPAMPMonitor" "$APP/Contents/MacOS/CPAMPMonitor"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -n "${APP_VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_VERSION" "$APP/Contents/Info.plist"
fi
swift scripts/make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"
codesign --force --deep --sign "${CODESIGN_IDENTITY:--}" --identifier local.cpamp.monitor "$APP"
codesign --verify --deep --strict "$APP"
printf '\nBuilt: %s\n' "$APP"
