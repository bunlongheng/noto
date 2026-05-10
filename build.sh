#!/bin/bash
# Build script for StickiesNative macOS app
# Usage: ./build.sh [--run]

set -e

SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
TARGET="arm64-apple-macosx14.0"
APP_NAME="StickiesNative"
SOURCES=$(find Sources -name "*.swift" | tr '\n' ' ')

echo "Building $APP_NAME..."

swiftc \
  -sdk "$SDK" \
  -target "$TARGET" \
  -parse-as-library \
  -O \
  -o "$APP_NAME" \
  $SOURCES

echo "Built: ./$APP_NAME"

# Create .app bundle
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
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.bheng.stickies-native</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>stickiesnative</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "Created: ./$APP_NAME.app"

if [ "$1" = "--run" ]; then
    echo "Launching..."
    open "$APP_NAME.app"
fi
