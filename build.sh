#!/bin/bash
# Build Noto into a signed .app bundle.
#
# Usage: ./build.sh [--run]
#
# Uses swiftc directly rather than SwiftPM: `swift build` cannot link its manifest
# on a CommandLineTools-only toolchain, which is the common setup here. Package.swift
# is kept so the project still opens and builds under full Xcode.
set -euo pipefail
cd "$(dirname "$0")"

SDK="${SDK:-$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)}"
APP_NAME="Noto"
DEPLOY="14.0"
SOURCES=$(find Sources -name "*.swift" | tr '\n' ' ')

mkdir -p .build

# Universal binary so the app also runs on Intel. Each slice is compiled
# separately and lipo'd; a single-arch build would exclude half of macOS.
echo "Building $APP_NAME (arm64 + x86_64)..."
for ARCH in arm64 x86_64; do
  swiftc -sdk "$SDK" -target "$ARCH-apple-macosx$DEPLOY" \
    -swift-version 6 -parse-as-library -O -o ".build/$APP_NAME-$ARCH" $SOURCES
done
lipo -create -output "$APP_NAME" ".build/$APP_NAME-arm64" ".build/$APP_NAME-x86_64"
echo "Built: ./$APP_NAME ($(lipo -archs "$APP_NAME"))"

APP_DIR="$APP_NAME.app/Contents/MacOS"

# Overwriting the binary of a RUNNING copy invalidates its signed pages, and the
# kernel then kills the process with SIGKILL (Code Signature Invalid) the moment
# it faults in a new one - it reads as a random crash while you are using the app.
if pgrep -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" > /dev/null; then
  echo "note: quitting the running $APP_NAME before replacing it"
  pkill -f "$APP_NAME.app/Contents/MacOS/$APP_NAME"
  sleep 1
fi

mkdir -p "$APP_DIR"
cp "$APP_NAME" "$APP_DIR/"

cat > "$APP_NAME.app/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Noto</string>
    <key>CFBundleIdentifier</key>
    <string>com.bheng.noto</string>
    <key>CFBundleName</key>
    <string>Noto</string>
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

# Signature. Ad-hoc by default; set SIGN_IDENTITY for a Developer ID build.
# Never silenced - a signing failure must fail the build, not print "Created".
codesign --force --options runtime --timestamp=none --sign "${SIGN_IDENTITY:--}" "$APP_NAME.app"
codesign --verify --strict "$APP_NAME.app"
echo "Signed: ${SIGN_IDENTITY:-ad-hoc}"
echo "Created: ./$APP_NAME.app"

# Keep /Applications in step. Without this, a rebuild updated the repo bundle while
# Launchpad, Spotlight and the Dock kept opening the OLD installed copy. Automatic
# once installed; --install puts it there the first time.
INSTALL_DIR="/Applications/$APP_NAME.app"
if [ -d "$INSTALL_DIR" ] || [ "${1:-}" = "--install" ]; then
  rm -rf "$INSTALL_DIR"
  cp -R "$APP_NAME.app" "$INSTALL_DIR"
  codesign --force --options runtime --timestamp=none --sign "${SIGN_IDENTITY:--}" "$INSTALL_DIR"
  echo "Installed: $INSTALL_DIR"
fi

if [ "${1:-}" = "--run" ] || [ "${1:-}" = "--install" ]; then
  echo "Launching..."
  # The installed copy when there is one: two bundles share an identifier, and
  # LaunchServices is free to pick either, so be explicit about which one runs.
  open "$([ -d "$INSTALL_DIR" ] && echo "$INSTALL_DIR" || echo "$APP_NAME.app")"
fi
