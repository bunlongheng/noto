#!/bin/bash
# Run the test suite.
#
# SwiftPM cannot run on a CommandLineTools-only toolchain (swift build fails to
# link the manifest), so this compiles the sources and Tests/ with swiftc directly -
# the same compiler build.sh uses. Identical locally and in CI.
set -e

SDK="${SDK:-$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)}"
TARGET="${TARGET:-arm64-apple-macosx14.0}"
OUT=".build/StickiesNativeTests"

# Every source except App.swift, which carries @main and would clash with the
# test executable's own entry point.
SOURCES=$(find Sources -name "*.swift" ! -name "App.swift" | tr '\n' ' ')
TESTS=$(find Tests -name "*.swift" | tr '\n' ' ')

mkdir -p .build
echo "Compiling tests..."
swiftc -sdk "$SDK" -target "$TARGET" -o "$OUT" $SOURCES $TESTS

echo "Running tests..."
"./$OUT"
