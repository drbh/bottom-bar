#!/bin/bash
set -e

APP_NAME="BottomBar"
BUNDLE_DIR=".build/${APP_NAME}.app"
CONTENTS="${BUNDLE_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
SIGNING_IDENTITY="Apple Development: David Holtz (47GRN2WUXL)"

swift build

rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS}"

cp .build/debug/${APP_NAME} "${MACOS}/${APP_NAME}"

cat > "${CONTENTS}/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.bottombar.app</string>
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
</dict>
</plist>
EOF

codesign --force --sign "${SIGNING_IDENTITY}" \
    --entitlements BottomBar.entitlements \
    "${BUNDLE_DIR}"

cp -R "${BUNDLE_DIR}" /Applications/${APP_NAME}.app

echo "Built, signed, and installed to /Applications/${APP_NAME}.app"
echo "Run with: open /Applications/${APP_NAME}.app"
