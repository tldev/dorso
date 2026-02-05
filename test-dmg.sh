#!/bin/bash
# Quick script to test DMG appearance without full release process

set -e

echo "Creating test DMG..."

# Unmount if already mounted
hdiutil detach /Volumes/Posturr 2>/dev/null || true

# Remove old test DMG
rm -f build/Posturr-test.dmg

# Make sure we have a built app
if [ ! -d "build/Posturr.app" ]; then
    echo "Building app first..."
    ./build.sh
fi

# Create DMG with new layout
create-dmg \
    --volname "Posturr" \
    --volicon "build/Posturr.app/Contents/Resources/AppIcon.icns" \
    --background "assets/dmg-background.png" \
    --window-pos 200 120 \
    --window-size 654 444 \
    --icon-size 140 \
    --text-size 12 \
    --icon "Posturr.app" 197 195 \
    --hide-extension "Posturr.app" \
    --app-drop-link 473 195 \
    "build/Posturr-test.dmg" \
    build/Posturr.app

echo ""
echo "Test DMG created: build/Posturr-test.dmg"
echo "Opening DMG to preview..."
open build/Posturr-test.dmg
