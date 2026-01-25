#!/bin/bash
# Create a DMG installer for Zeit
set -e

VERSION="${1:-0.1.0}"
APP_PATH="${2:-dist/Zeit.app}"
DMG_NAME="Zeit-${VERSION}"
DMG_PATH="dist/${DMG_NAME}.dmg"
VOLUME_NAME="Zeit"
TEMP_DMG="dist/${DMG_NAME}-temp.dmg"

echo "Creating DMG for Zeit v${VERSION}..."

# Check that app exists
if [ ! -d "$APP_PATH" ]; then
    echo "Error: $APP_PATH not found. Build the app first with build_all.sh"
    exit 1
fi

# Clean up any existing DMG
rm -f "$DMG_PATH" "$TEMP_DMG"

# Create temporary directory for DMG contents
STAGING_DIR=$(mktemp -d)
trap "rm -rf $STAGING_DIR" EXIT

echo "Staging DMG contents..."

# Copy app to staging
cp -R "$APP_PATH" "$STAGING_DIR/"

# Create symlink to Applications
ln -s /Applications "$STAGING_DIR/Applications"

# Create the DMG
echo "Creating DMG image..."
hdiutil create -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov -format UDRW \
    "$TEMP_DMG"

# Convert to compressed read-only DMG
echo "Compressing DMG..."
hdiutil convert "$TEMP_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_PATH"

# Clean up temp DMG
rm -f "$TEMP_DMG"

echo ""
echo "DMG created: $DMG_PATH"

# Show file size
ls -lh "$DMG_PATH"
