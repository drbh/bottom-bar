#!/bin/bash
# Builds the plugin and installs it as a .bundle in ~/.bottombar/plugins/
set -euo pipefail

PLUGIN_NAME="HelloPlugin"
BUNDLE_NAME="${PLUGIN_NAME}.bundle"
PLUGINS_DIR="$HOME/.bottombar/plugins"
BUNDLE_DIR="${PLUGINS_DIR}/${BUNDLE_NAME}"

echo "Building ${PLUGIN_NAME}..."
swift build

echo "Installing to ${BUNDLE_DIR}..."
rm -rf "${BUNDLE_DIR}"
mkdir -p "${BUNDLE_DIR}/Contents/MacOS"
mkdir -p "${BUNDLE_DIR}/Contents"

cp .build/debug/libHelloPlugin.dylib "${BUNDLE_DIR}/Contents/MacOS/${PLUGIN_NAME}"
cp Sources/HelloPlugin/Info.plist "${BUNDLE_DIR}/Contents/Info.plist"

echo "Done! ${BUNDLE_NAME} installed to ${PLUGINS_DIR}"
