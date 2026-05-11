#!/bin/bash
# Builds all plugins and installs them to ~/.bottombar/plugins/
set -euo pipefail

PLUGINS_DIR="$HOME/.bottombar/plugins"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$PLUGINS_DIR"

for plugin_dir in "$SCRIPT_DIR"/*/; do
    [ -f "$plugin_dir/Package.swift" ] || continue

    plugin_name=$(basename "$plugin_dir")
    bundle_dir="$PLUGINS_DIR/${plugin_name}.bundle"

    echo "Building $plugin_name..."
    (cd "$plugin_dir" && swift build 2>&1)

    echo "Installing $plugin_name..."
    rm -rf "$bundle_dir"
    mkdir -p "$bundle_dir/Contents/MacOS"

    cp "$plugin_dir/.build/debug/lib${plugin_name}.dylib" "$bundle_dir/Contents/MacOS/$plugin_name"
    cp "$plugin_dir/Sources/Info.plist" "$bundle_dir/Contents/Info.plist"

    echo "  -> $bundle_dir"
done

echo ""
echo "All plugins installed to $PLUGINS_DIR"
