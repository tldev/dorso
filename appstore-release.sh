#!/bin/bash

# Posturr App Store Release Script
# Builds, signs, and packages the app for App Store submission
#
# Prerequisites:
#   1. Apple Developer account with App Store Connect access
#   2. "Apple Distribution" certificate installed in Keychain
#   3. App-specific provisioning profile (Mac App Store)
#   4. App record created in App Store Connect
#
# Usage:
#   ./appstore-release.sh
#
# The script will:
#   1. Build the app without private APIs
#   2. Sign with your Apple Distribution certificate
#   3. Create a .pkg for App Store upload
#   4. Validate the package

set -e

# Configuration - UPDATE THESE VALUES
APP_NAME="Posturr"
BUNDLE_ID="com.thelazydeveloper.posturr"  # Must match App Store Connect
VERSION="1.0.8"
MIN_MACOS="13.0"

# Signing identity (find yours with: security find-identity -v -p codesigning)
# Use "Apple Distribution" for App Store, or "3rd Party Mac Developer Application" for older certs
SIGNING_IDENTITY="Apple Distribution"
INSTALLER_IDENTITY="3rd Party Mac Developer Installer"

# Team ID (find in Apple Developer portal or Keychain certificate details)
TEAM_ID="KBF2YGT2KP"

# Directories
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build-appstore"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Building $APP_NAME v$VERSION for App Store${NC}"
echo ""

# Validate configuration
if [ -z "$TEAM_ID" ]; then
    echo -e "${RED}Error: TEAM_ID is not set${NC}"
    echo "Please edit this script and set your Team ID"
    echo "You can find it in the Apple Developer portal or in your certificate details"
    exit 1
fi

# Clean previous build
if [ -d "$BUILD_DIR" ]; then
    echo "Cleaning previous App Store build..."
    rm -rf "$BUILD_DIR"
fi

# Create directory structure
echo "Creating app bundle structure..."
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Compile Swift code WITHOUT private APIs
echo "Compiling main.swift (App Store build - no private APIs)..."
swiftc \
    -O \
    -whole-module-optimization \
    -D APP_STORE \
    -target arm64-apple-macos$MIN_MACOS \
    -sdk $(xcrun --show-sdk-path) \
    -framework AppKit \
    -framework AVFoundation \
    -framework Vision \
    -framework CoreImage \
    -o "$MACOS_DIR/$APP_NAME" \
    "$SCRIPT_DIR/main.swift"

# Create universal binary
if [[ $(uname -m) == "arm64" ]]; then
    echo "Creating universal binary (arm64 + x86_64)..."
    swiftc \
        -O \
        -whole-module-optimization \
        -D APP_STORE \
        -target x86_64-apple-macos$MIN_MACOS \
        -sdk $(xcrun --show-sdk-path) \
        -framework AppKit \
        -framework AVFoundation \
        -framework Vision \
        -framework CoreImage \
        -o "$MACOS_DIR/${APP_NAME}_x86" \
        "$SCRIPT_DIR/main.swift"

    lipo -create -output "$MACOS_DIR/$APP_NAME" \
        "$MACOS_DIR/$APP_NAME" \
        "$MACOS_DIR/${APP_NAME}_x86"

    rm "$MACOS_DIR/${APP_NAME}_x86"
fi

# Create Info.plist with App Store required keys
echo "Creating Info.plist..."
cat > "$CONTENTS/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSCameraUsageDescription</key>
    <string>Posturr needs camera access to monitor your posture and blur the screen when you slouch.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.healthcare-fitness</string>
    <key>ITSAppUsesNonExemptEncryption</key>
    <false/>
</dict>
</plist>
EOF

# Copy icon
if [ -f "$SCRIPT_DIR/AppIcon.icns" ]; then
    echo "Copying app icon..."
    cp "$SCRIPT_DIR/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
elif [ -d "$SCRIPT_DIR/Posturr.iconset" ]; then
    echo "Converting iconset to icns..."
    iconutil -c icns -o "$RESOURCES_DIR/AppIcon.icns" "$SCRIPT_DIR/Posturr.iconset"
fi

# Create entitlements (App Sandbox required for App Store)
echo "Creating App Store entitlements..."
cat > "$BUILD_DIR/Posturr.entitlements" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.device.camera</key>
    <true/>
</dict>
</plist>
EOF

chmod +x "$MACOS_DIR/$APP_NAME"

# Sign the app with Apple Distribution certificate
echo "Signing app bundle for App Store..."
codesign --force --deep --options runtime \
    --entitlements "$BUILD_DIR/Posturr.entitlements" \
    --sign "$SIGNING_IDENTITY" \
    --timestamp \
    "$APP_BUNDLE"

# Verify signature
echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

# Create installer package for App Store
echo "Creating installer package..."
PKG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.pkg"
productbuild \
    --component "$APP_BUNDLE" /Applications \
    --sign "$INSTALLER_IDENTITY" \
    "$PKG_PATH"

# Validate the package
echo "Validating package for App Store..."
xcrun altool --validate-app -f "$PKG_PATH" -t macos --apiKey "" --apiIssuer "" 2>/dev/null || {
    echo -e "${YELLOW}Note: Package validation requires App Store Connect API credentials${NC}"
    echo "You can validate manually with Transporter app or upload directly to App Store Connect"
}

echo ""
echo -e "${GREEN}App Store build complete!${NC}"
echo ""
echo "Output files:"
echo "  App Bundle: $APP_BUNDLE"
echo "  Installer:  $PKG_PATH"
echo ""
echo "Next steps:"
echo "  1. Open Transporter app (from Mac App Store)"
echo "  2. Drag $PKG_PATH into Transporter"
echo "  3. Click 'Deliver' to upload to App Store Connect"
echo ""
echo "Or use the command line:"
echo "  xcrun altool --upload-app -f \"$PKG_PATH\" -t macos --apiKey YOUR_KEY --apiIssuer YOUR_ISSUER"
echo ""
