#!/bin/bash
set -e

echo "================================================"
echo "Building Zeit (Swift)"
echo "================================================"

# Parse arguments
BUILD_TYPE="debug"
INSTALL=false
CREATE_DMG=false
CLEAN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --release) BUILD_TYPE="release"; shift ;;
        --install) INSTALL=true; shift ;;
        --dmg) CREATE_DMG=true; shift ;;
        --clean) CLEAN=true; shift ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --release     Build in release mode (optimized)"
            echo "  --install     Install to /Applications after building"
            echo "  --dmg         Create DMG installer"
            echo "  --clean       Clean build artifacts before building"
            echo "  -h, --help    Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  LOCAL_SIGNING_IDENTITY  Signing identity (default: Zeit Local Signing)"
            echo ""
            echo "Examples:"
            echo "  $0                          # Debug build"
            echo "  $0 --release --install      # Release build and install"
            echo "  $0 --release --dmg          # Release build with DMG"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Use committed git hooks
git config core.hooksPath scripts/hooks

BUILD_DIR=".build"
DIST_DIR="dist"
APP_NAME="Zeit"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
VERSION="0.2.0"

# Full Xcode is needed for actool (asset catalogs) and the Metal compiler, even
# when xcode-select points at the Command Line Tools
XCODE_DEV_DIR="/Applications/Xcode.app/Contents/Developer"
if [ -d "$XCODE_DEV_DIR" ]; then
    export DEVELOPER_DIR="$XCODE_DEV_DIR"
fi

# Auto-clean if Swift compiler version changed
SWIFT_VERSION=$(swift --version 2>&1 | head -1)
SWIFT_VERSION_FILE="$BUILD_DIR/.swift-version-used"
if [ -f "$SWIFT_VERSION_FILE" ]; then
    CACHED_VERSION=$(cat "$SWIFT_VERSION_FILE")
    if [ "$CACHED_VERSION" != "$SWIFT_VERSION" ]; then
        echo ""
        echo "Swift compiler changed:"
        echo "  was: $CACHED_VERSION"
        echo "  now: $SWIFT_VERSION"
        echo "Auto-cleaning build artifacts..."
        CLEAN=true
    fi
fi

# Clean if requested or auto-triggered
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

# Record Swift version for future change detection
mkdir -p "$BUILD_DIR"
echo "$SWIFT_VERSION" > "$SWIFT_VERSION_FILE"

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

# Compile MLX Metal shaders into metallib (with caching)
echo ""
echo "Compiling MLX Metal shaders..."
echo "----------------------------------------"

MLX_METAL_DIR="$BUILD_DIR/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal"
METAL_BUILD_DIR="$BUILD_DIR/metal-shaders"
METALLIB_CACHE="$METAL_BUILD_DIR/mlx.metallib"
METALLIB_HASH_FILE="$METAL_BUILD_DIR/.metal_sources_hash"

# Compute hash of all .metal source files
CURRENT_HASH=$(find "$MLX_METAL_DIR" -name "*.metal" -exec shasum {} \; | sort | shasum | awk '{print $1}')

METAL_CACHED=false
if [ -f "$METALLIB_CACHE" ] && [ -f "$METALLIB_HASH_FILE" ]; then
    CACHED_HASH=$(cat "$METALLIB_HASH_FILE")
    if [ "$CURRENT_HASH" = "$CACHED_HASH" ]; then
        echo "  Metal shaders unchanged, using cached mlx.metallib"
        METAL_CACHED=true
    fi
fi

if [ "$METAL_CACHED" = false ]; then
    rm -rf "$METAL_BUILD_DIR"
    mkdir -p "$METAL_BUILD_DIR"

    # Metal compiler requires full Xcode (not just CommandLineTools)
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
    DEVELOPER_DIR="$XCODE_DEV_DIR" xcrun -sdk macosx metallib "${KERNEL_AIR_FILES[@]}" -o "$METALLIB_CACHE"

    # Save hash for next build
    echo "$CURRENT_HASH" > "$METALLIB_HASH_FILE"
    echo "Metal shaders compiled"
fi

# Place metallib next to the binary (MLX looks here first via current_binary_dir())
cp "$METALLIB_CACHE" "$APP_BUNDLE/Contents/MacOS/mlx.metallib"
echo "Metal shaders bundled"

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

# A stable identity is what keeps the privacy grants across reinstalls: the
# designated requirement then names the certificate instead of the binary, so
# the grant given to one build still matches the next. See
# scripts/make-signing-cert.sh. An ad-hoc signature is not a usable fallback —
# it names a hash of the binary, which every build changes, and the user pays
# for it by granting both permissions again.
LOCAL_SIGNING_IDENTITY="${LOCAL_SIGNING_IDENTITY:-Zeit Local Signing}"

if ! security find-identity -p codesigning | grep -qF "$LOCAL_SIGNING_IDENTITY"; then
    echo "Error: no \"$LOCAL_SIGNING_IDENTITY\" identity in the keychain."
    echo "  Create it once with ./scripts/make-signing-cert.sh"
    echo "  Or use swift build, which needs no app bundle."
    exit 1
fi

echo "Signing with: $LOCAL_SIGNING_IDENTITY"
codesign --force --sign "$LOCAL_SIGNING_IDENTITY" "$APP_BUNDLE/Contents/MacOS/mlx.metallib"
codesign --force --sign "$LOCAL_SIGNING_IDENTITY" "$APP_BUNDLE"

# Verify signature
codesign --verify --verbose "$APP_BUNDLE"
echo "Signature verified"

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

    echo "DMG created: $DMG_PATH"
fi

# Install if requested
if [ "$INSTALL" = true ]; then
    echo ""
    echo "Installing..."
    echo "----------------------------------------"

    # Take the jobs out of the login session before the bundle goes. launchd
    # keeps the menubar app alive by path, so replacing the bundle under a
    # running job leaves launchd with no program to start and it drops the job
    # from the domain, which is why the app did not come back on its own.
    LAUNCHD_DOMAIN="gui/$(id -u)"
    TRACKER_LABEL="co.invariante.zeit"
    MENUBAR_LABEL="co.invariante.zeit.menubar"

    echo "Stopping services..."
    for label in "$TRACKER_LABEL" "$MENUBAR_LABEL"; do
        launchctl bootout "$LAUNCHD_DOMAIN/$label" 2>/dev/null || true
    done

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

    # Absent on a fresh account, and the plists below are written into it.
    mkdir -p "$HOME/Library/LaunchAgents"

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
        <string>/Applications/$APP_NAME.app/Contents/MacOS/$APP_NAME</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
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

    # The menubar app clears the tracking stop flag as it starts, so tracking
    # resumes by itself once the job is back.
    echo ""
    echo "Starting services..."
    launchctl bootstrap "$LAUNCHD_DOMAIN" "$TRACKER_PLIST"
    launchctl bootstrap "$LAUNCHD_DOMAIN" "$MENUBAR_PLIST"
    launchctl print "$LAUNCHD_DOMAIN/$MENUBAR_LABEL" >/dev/null 2>&1 \
        && echo "  $MENUBAR_LABEL running" \
        || echo "  Warning: $MENUBAR_LABEL did not start"
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
