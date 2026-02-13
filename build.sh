#!/bin/bash
set -e

echo "================================================"
echo "Building Zeit (Swift)"
echo "================================================"

# Parse arguments
BUILD_TYPE="debug"
INSTALL=false
SIGN=false
NOTARIZE=false
CREATE_DMG=false
CLEAN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --release) BUILD_TYPE="release"; shift ;;
        --install) INSTALL=true; shift ;;
        --sign) SIGN=true; shift ;;
        --notarize) NOTARIZE=true; SIGN=true; shift ;;
        --dmg) CREATE_DMG=true; shift ;;
        --clean) CLEAN=true; shift ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --release     Build in release mode (optimized)"
            echo "  --install     Install to /Applications after building"
            echo "  --sign        Sign with Developer ID (requires DEVELOPER_ID env var)"
            echo "  --notarize    Notarize with Apple (requires --sign, NOTARIZE_PROFILE env var)"
            echo "  --dmg         Create DMG installer"
            echo "  --clean       Clean build artifacts before building"
            echo "  -h, --help    Show this help message"
            echo ""
            echo "Environment variables for signing:"
            echo "  DEVELOPER_ID       Developer ID certificate name"
            echo "  NOTARIZE_PROFILE   Keychain profile for notarytool credentials"
            echo ""
            echo "Examples:"
            echo "  $0                          # Debug build"
            echo "  $0 --release --install      # Release build and install"
            echo "  $0 --release --sign --dmg   # Signed release with DMG"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BUILD_DIR=".build"
DIST_DIR="dist"
APP_NAME="Zeit"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
VERSION="0.2.0"

# Load signing environment if available
if [ -f ../.env.signing ]; then
    source ../.env.signing
fi

# Validate signing requirements
if [ "$SIGN" = true ]; then
    if [ -z "$DEVELOPER_ID" ]; then
        echo "Error: --sign requires DEVELOPER_ID environment variable"
        echo "Example: export DEVELOPER_ID=\"Developer ID Application: Your Name (TEAM_ID)\""
        exit 1
    fi
    echo "Signing with: $DEVELOPER_ID"
fi

if [ "$NOTARIZE" = true ]; then
    if [ -z "$NOTARIZE_PROFILE" ]; then
        echo "Error: --notarize requires NOTARIZE_PROFILE environment variable"
        echo "Create profile: xcrun notarytool store-credentials \"zeit-notarize\" ..."
        exit 1
    fi
    echo "Notarization profile: $NOTARIZE_PROFILE"
fi

# Clean if requested
if [ "$CLEAN" = true ]; then
    echo ""
    echo "Cleaning build artifacts..."
    rm -rf "$BUILD_DIR"
    rm -rf "$DIST_DIR"
fi

# Build
echo ""
echo "Building ($BUILD_TYPE)..."
echo "----------------------------------------"

if [ "$BUILD_TYPE" = "release" ]; then
    swift build -c release
    BINARY_PATH="$BUILD_DIR/release/ZeitApp"
else
    swift build
    BINARY_PATH="$BUILD_DIR/debug/ZeitApp"
fi

echo "Binary built: $BINARY_PATH"

# Create app bundle
echo ""
echo "Creating app bundle..."
echo "----------------------------------------"

mkdir -p "$DIST_DIR"
rm -rf "$APP_BUNDLE"

# Create bundle structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Compile MLX Metal shaders into metallib
echo ""
echo "Compiling MLX Metal shaders..."
echo "----------------------------------------"

MLX_METAL_DIR="$BUILD_DIR/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal"
METAL_BUILD_DIR="$BUILD_DIR/metal-shaders"
rm -rf "$METAL_BUILD_DIR"
mkdir -p "$METAL_BUILD_DIR"

# Metal compiler requires full Xcode (not just CommandLineTools)
XCODE_DEV_DIR="/Applications/Xcode.app/Contents/Developer"
if [ ! -d "$XCODE_DEV_DIR" ]; then
    echo "Error: Xcode not found at /Applications/Xcode.app"
    echo "Full Xcode installation is required to compile Metal shaders."
    echo "Also run: xcodebuild -downloadComponent MetalToolchain"
    exit 1
fi

METAL_FLAGS="-Wall -Wextra -fno-fast-math -Wno-c++17-extensions -mmacosx-version-min=14.0"
METAL_INCLUDE="$MLX_METAL_DIR"
# macOS 14 = Metal 3.1
METAL_VERSION_INCLUDE="$MLX_METAL_DIR/metal_3_1"

KERNEL_AIR_FILES=()
for metal_file in $(find "$MLX_METAL_DIR" -name "*.metal"); do
    kernel_name=$(basename "$metal_file" .metal)
    air_file="$METAL_BUILD_DIR/${kernel_name}.air"
    echo "  Compiling: $(basename "$metal_file")"
    DEVELOPER_DIR="$XCODE_DEV_DIR" xcrun -sdk macosx metal $METAL_FLAGS \
        -c "$metal_file" \
        -I"$METAL_INCLUDE" \
        -I"$METAL_VERSION_INCLUDE" \
        -o "$air_file"
    KERNEL_AIR_FILES+=("$air_file")
done

echo "  Linking ${#KERNEL_AIR_FILES[@]} kernels into mlx.metallib..."
DEVELOPER_DIR="$XCODE_DEV_DIR" xcrun -sdk macosx metallib "${KERNEL_AIR_FILES[@]}" -o "$METAL_BUILD_DIR/mlx.metallib"

# Place metallib next to the binary (MLX looks here first via current_binary_dir())
cp "$METAL_BUILD_DIR/mlx.metallib" "$APP_BUNDLE/Contents/MacOS/mlx.metallib"
echo "Metal shaders compiled and bundled"

# Copy SPM resource bundles
echo ""
echo "Copying resource bundles..."
if [ "$BUILD_TYPE" = "release" ]; then
    BUNDLE_DIR="$BUILD_DIR/arm64-apple-macosx/release"
else
    BUNDLE_DIR="$BUILD_DIR/arm64-apple-macosx/debug"
fi
for bundle in "$BUNDLE_DIR"/*.bundle; do
    if [ -d "$bundle" ]; then
        echo "  $(basename "$bundle")"
        cp -R "$bundle" "$APP_BUNDLE/Contents/Resources/"
    fi
done

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>co.invariante.zeit</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Zeit needs screen recording access to capture screenshots and track your activities.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Zeit needs automation access to detect the active window and application.</string>
</dict>
</plist>
EOF

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "App bundle created: $APP_BUNDLE"

# Clear quarantine attributes
echo "Clearing quarantine attributes..."
xattr -cr "$APP_BUNDLE" 2>/dev/null || true

# Code sign
echo ""
echo "Code signing..."
echo "----------------------------------------"

if [ "$SIGN" = true ]; then
    # Create entitlements file
    cat > "$DIST_DIR/entitlements.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
    <key>com.apple.security.device.camera</key>
    <false/>
    <key>com.apple.security.personal-information.photos-library</key>
    <false/>
</dict>
</plist>
EOF

    echo "Signing with Developer ID..."
    # Sign the metallib before signing the main bundle
    codesign --force --options runtime --sign "$DEVELOPER_ID" \
        "$APP_BUNDLE/Contents/MacOS/mlx.metallib" 2>/dev/null || true
    # Sign the main bundle
    codesign --force --options runtime \
        --sign "$DEVELOPER_ID" \
        --entitlements "$DIST_DIR/entitlements.plist" \
        "$APP_BUNDLE"
else
    echo "Signing ad-hoc..."
    # Sign the metallib before signing the main bundle
    codesign --force --sign - "$APP_BUNDLE/Contents/MacOS/mlx.metallib" 2>/dev/null || true
    # Sign the main bundle
    codesign --force --sign - "$APP_BUNDLE"
fi

# Verify signature
codesign --verify --verbose "$APP_BUNDLE"
echo "Signature verified"

# Notarize if requested
if [ "$NOTARIZE" = true ]; then
    echo ""
    echo "Notarizing..."
    echo "----------------------------------------"

    # Create zip for notarization
    echo "Creating zip for notarization..."
    ditto -c -k --keepParent "$APP_BUNDLE" "$DIST_DIR/$APP_NAME.zip"

    # Submit for notarization
    echo "Submitting to Apple (this may take a few minutes)..."
    xcrun notarytool submit "$DIST_DIR/$APP_NAME.zip" \
        --keychain-profile "$NOTARIZE_PROFILE" \
        --wait

    # Staple the ticket
    echo "Stapling notarization ticket..."
    xcrun stapler staple "$APP_BUNDLE"

    # Clean up zip
    rm "$DIST_DIR/$APP_NAME.zip"

    # Verify
    echo "Verifying notarization..."
    spctl -a -v "$APP_BUNDLE"

    echo "Notarization complete!"
fi

# Create DMG if requested
if [ "$CREATE_DMG" = true ]; then
    echo ""
    echo "Creating DMG..."
    echo "----------------------------------------"

    DMG_NAME="$APP_NAME-$VERSION.dmg"
    DMG_PATH="$DIST_DIR/$DMG_NAME"

    # Remove existing DMG
    rm -f "$DMG_PATH"

    # Create temporary DMG directory
    DMG_TEMP="$DIST_DIR/dmg_temp"
    rm -rf "$DMG_TEMP"
    mkdir -p "$DMG_TEMP"

    # Copy app to temp directory
    cp -R "$APP_BUNDLE" "$DMG_TEMP/"

    # Create symlink to Applications
    ln -s /Applications "$DMG_TEMP/Applications"

    # Create DMG
    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$DMG_TEMP" \
        -ov -format UDZO \
        "$DMG_PATH"

    # Clean up
    rm -rf "$DMG_TEMP"

    # Sign DMG if signing is enabled
    if [ "$SIGN" = true ]; then
        echo "Signing DMG..."
        codesign --force --sign "$DEVELOPER_ID" "$DMG_PATH"
    fi

    echo "DMG created: $DMG_PATH"
fi

# Install if requested
if [ "$INSTALL" = true ]; then
    echo ""
    echo "Installing..."
    echo "----------------------------------------"

    # Copy to /Applications
    echo "Copying to /Applications..."
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP_BUNDLE" "/Applications/"

    # Create CLI symlink
    CLI_LINK="$HOME/.local/bin/zeit"
    mkdir -p "$(dirname "$CLI_LINK")"
    rm -f "$CLI_LINK"
    ln -s "/Applications/$APP_NAME.app/Contents/MacOS/$APP_NAME" "$CLI_LINK"

    echo "Installed to /Applications/$APP_NAME.app"
    echo "CLI symlink: $CLI_LINK"

    # Update LaunchAgents
    echo ""
    echo "Updating LaunchAgents..."

    TRACKER_PLIST="$HOME/Library/LaunchAgents/co.invariante.zeit.plist"
    MENUBAR_PLIST="$HOME/Library/LaunchAgents/co.invariante.zeit.menubar.plist"

    # Create tracker plist
    cat > "$TRACKER_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>co.invariante.zeit</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/$APP_NAME.app/Contents/MacOS/$APP_NAME</string>
        <string>track</string>
    </array>
    <key>StartInterval</key>
    <integer>60</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/zeit/tracker.out.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/zeit/tracker.err.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key>
        <string>$HOME</string>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
    <key>WorkingDirectory</key>
    <string>$HOME/.local/share/zeit</string>
</dict>
</plist>
EOF

    # Create menubar plist
    cat > "$MENUBAR_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>co.invariante.zeit.menubar</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-a</string>
        <string>/Applications/$APP_NAME.app</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/zeit/menubar.out.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/zeit/menubar.err.log</string>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
EOF

    # Ensure logs directory exists
    mkdir -p "$HOME/Library/Logs/zeit"

    echo "LaunchAgents updated"
    echo ""
    echo "To reload services, run:"
    echo "  launchctl bootout gui/\$(id -u)/co.invariante.zeit 2>/dev/null || true"
    echo "  launchctl bootout gui/\$(id -u)/co.invariante.zeit.menubar 2>/dev/null || true"
    echo "  launchctl bootstrap gui/\$(id -u) $TRACKER_PLIST"
    echo "  launchctl bootstrap gui/\$(id -u) $MENUBAR_PLIST"
fi

echo ""
echo "================================================"
echo "Build complete!"
echo "================================================"
echo ""
echo "Output: $APP_BUNDLE"
[ "$CREATE_DMG" = true ] && echo "DMG: $DIST_DIR/$APP_NAME-$VERSION.dmg"
echo ""
echo "To test CLI:"
echo "  $APP_BUNDLE/Contents/MacOS/$APP_NAME --help"
echo "  $APP_BUNDLE/Contents/MacOS/$APP_NAME doctor"
echo ""
echo "To test GUI (menubar):"
echo "  open $APP_BUNDLE"
