#!/bin/bash
# Build BottomBar, wrap in .app bundle, and codesign with entitlements.
set -euo pipefail

swift build "$@"

APP_DIR=".build/debug/BottomBar.app/Contents"
mkdir -p "$APP_DIR/MacOS" "$APP_DIR/Frameworks"
cp .build/debug/BottomBar "$APP_DIR/MacOS/BottomBar"
cp .build/debug/libBottomBarSDK.dylib "$APP_DIR/Frameworks/libBottomBarSDK.dylib"
cp Sources/BottomBar/Info.plist "$APP_DIR/Info.plist"

# Fix rpath so the binary finds the SDK in Frameworks/
install_name_tool -add_rpath @executable_path/../Frameworks "$APP_DIR/MacOS/BottomBar" 2>/dev/null || true

codesign --force --sign - --entitlements BottomBar.entitlements "$APP_DIR/MacOS/BottomBar"
echo "Built and codesigned BottomBar.app"
