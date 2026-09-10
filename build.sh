#!/bin/bash
# Build StickiesNative into a signed .app bundle.
#
# Usage: ./build.sh [--run]
#
# Uses swiftc directly rather than SwiftPM: `swift build` cannot link its manifest
# on a CommandLineTools-only toolchain, which is the common setup here. Package.swift
# is kept so the project still opens and builds under full Xcode.
set -e

SDK="${SDK:-$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)}"
APP_NAME="StickiesNative"
DEPLOY="14.0"
SOURCES=$(find Sources -name "*.swift" | tr '\n' ' ')

mkdir -p .build

# Universal binary so the app also runs on Intel. Each slice is compiled
# separately and lipo'd; a single-arch build would exclude half of macOS.
echo "Building $APP_NAME (arm64 + x86_64)..."
for ARCH in arm64 x86_64; do
  swiftc -sdk "$SDK" -target "$ARCH-apple-macosx$DEPLOY" \
    -parse-as-library -O -o ".build/$APP_NAME-$ARCH" $SOURCES
done
lipo -create -output "$APP_NAME" ".build/$APP_NAME-arm64" ".build/$APP_NAME-x86_64"
echo "Built: ./$APP_NAME ($(lipo -archs "$APP_NAME"))"

APP_DIR="$APP_NAME.app/Contents/MacOS"
mkdir -p "$APP_DIR"
cp "$APP_NAME" "$APP_DIR/"

cat > "$APP_NAME.app/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>StickiesNative</string>
    <key>CFBundleIdentifier</key>
    <string>com.bheng.stickies-native</string>
    <key>CFBundleName</key>
    <string>Stickies Native</string>
    <key>CFBundleVersion</key>
    <string>2.0</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST

RESOURCES_DIR="$APP_NAME.app/Contents/Resources"
mkdir -p "$RESOURCES_DIR"
if [ -f AppIcon.icns ]; then
  cp AppIcon.icns "$RESOURCES_DIR/"
else
  echo "note: no AppIcon.icns, using the default icon"
fi

# Ad-hoc signature so Gatekeeper allows the local build.
codesign --force --deep --sign - "$APP_NAME.app" 2>/dev/null && echo "Signed (ad-hoc)"
echo "Created: ./$APP_NAME.app"

if [ "$1" = "--run" ]; then
  echo "Launching..."
  open "$APP_NAME.app"
fi
