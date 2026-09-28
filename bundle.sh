#!/bin/bash
set -euo pipefail

APP_NAME="BottomBar"
BUNDLE_DIR=".build/${APP_NAME}.app"
CONTENTS="${BUNDLE_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
FRAMEWORKS="${CONTENTS}/Frameworks"
DEST_DIR="${DEST_DIR:-/Applications}"
DEST_APP="${DEST_DIR}/${APP_NAME}.app"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

swift build

rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS}" "${FRAMEWORKS}"

cp .build/debug/${APP_NAME} "${MACOS}/${APP_NAME}"
cp .build/debug/libBottomBarSDK.dylib "${FRAMEWORKS}/libBottomBarSDK.dylib"

cat > "${CONTENTS}/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.drbh.BottomBar</string>
    <key>CFBundleName</key>
    <string>BottomBar</string>
    <key>CFBundleExecutable</key>
    <string>BottomBar</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>BottomBar uses your location to display your current city.</string>
    <key>NSLocationUsageDescription</key>
    <string>BottomBar uses your location to display your current city.</string>
    <key>NSCameraUsageDescription</key>
    <string>BottomBar launches MiniMe which uses the camera.</string>
</dict>
</plist>
EOF

install_name_tool -add_rpath @executable_path/../Frameworks "${MACOS}/${APP_NAME}" 2>/dev/null || true

codesign --force --sign "${SIGNING_IDENTITY}" \
    "${FRAMEWORKS}/libBottomBarSDK.dylib"
codesign --force --sign "${SIGNING_IDENTITY}" \
    --entitlements BottomBar.entitlements \
    "${BUNDLE_DIR}"

pkill -x "${APP_NAME}" 2>/dev/null || true
rm -rf "${DEST_APP}"
ditto "${BUNDLE_DIR}" "${DEST_APP}"

echo "Built, signed, and installed to ${DEST_APP}"
echo "Run with: open ${DEST_APP}"
