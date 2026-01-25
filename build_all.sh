#!/bin/bash
set -e

echo "================================================"
echo "Building Zeit - Complete Package"
echo "================================================"

# Parse arguments
SKIP_CLI=false
SKIP_APP=false
SKIP_CHECKS=false
INSTALL=false
LOCAL_APP=false
CREATE_DMG=false
SIGN=false
NOTARIZE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-cli) SKIP_CLI=true; shift ;;
        --skip-app) SKIP_APP=true; shift ;;
        --skip-checks) SKIP_CHECKS=true; shift ;;
        --install) INSTALL=true; shift ;;
        --local) LOCAL_APP=true; shift ;;
        --dmg) CREATE_DMG=true; shift ;;
        --sign) SIGN=true; shift ;;
        --notarize) NOTARIZE=true; SIGN=true; shift ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-cli      Skip building CLI binary"
            echo "  --skip-app      Skip building menubar app"
            echo "  --skip-checks   Skip code quality checks"
            echo "  --install       Install after building"
            echo "  --local         Build in development mode (fast, local only)"
            echo "  --dmg           Create DMG installer after building app"
            echo "  --sign          Sign with Developer ID (requires DEVELOPER_ID env var)"
            echo "  --notarize      Notarize with Apple (requires --sign, NOTARIZE_PROFILE env var)"
            echo "  -h, --help      Show this help message"
            echo ""
            echo "Environment variables for signing:"
            echo "  DEVELOPER_ID       Developer ID certificate name"
            echo "  NOTARIZE_PROFILE   Keychain profile for notarytool credentials"
            echo ""
            echo "Examples:"
            echo "  $0 --local --install          # Fast dev build"
            echo "  $0 --install                  # Distribution build"
            echo "  $0 --sign --notarize --dmg    # Signed release"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Load signing environment if available
if [ -f .env.signing ]; then
    source .env.signing
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

# Ensure dependencies
echo ""
echo "Syncing dependencies..."
uv sync

# Run code quality checks
if [ "$SKIP_CHECKS" = false ]; then
    echo ""
    echo "Running code quality checks..."
    echo "----------------------------------------"

    echo "Checking formatting..."
    uv run ruff format --check . || { echo "Format check failed. Run: uv run ruff format ."; exit 1; }

    echo "Checking linting..."
    uv run ruff check . || { echo "Lint check failed. Run: uv run ruff check --fix ."; exit 1; }

    echo "Checking types..."
    uv run mypy src/ || { echo "Type check failed."; exit 1; }

    echo "All checks passed!"
fi

# Build CLI with PyInstaller (FIRST, so it can be bundled in app)
if [ "$SKIP_CLI" = false ]; then
    echo ""
    echo "Building CLI (PyInstaller)..."
    echo "----------------------------------------"

    # Clean previous build
    rm -rf build/zeit_cli dist/zeit

    # Run PyInstaller
    uv run pyinstaller zeit_cli.spec --noconfirm

    # Clear quarantine attributes to avoid macOS security scanning delays
    echo "Clearing quarantine attributes..."
    xattr -cr dist/zeit/

    # Code sign the executable
    if [ "$SIGN" = true ]; then
        echo "Code signing CLI with Developer ID..."
        codesign --force --options runtime --sign "$DEVELOPER_ID" \
            --entitlements entitlements.plist \
            dist/zeit/zeit
    else
        echo "Code signing CLI (ad-hoc)..."
        codesign --force --sign - dist/zeit/zeit
    fi

    echo "CLI built: dist/zeit/zeit"
fi

# Build menubar app with py2app
if [ "$SKIP_APP" = false ]; then
    echo ""
    if [ "$LOCAL_APP" = true ]; then
        echo "Building menubar app (py2app - alias/development mode)..."
    else
        echo "Building menubar app (py2app - distribution mode)..."
    fi
    echo "----------------------------------------"

    # Verify CLI binary exists (needed for bundling)
    if [ ! -f dist/zeit/zeit ]; then
        echo "Warning: CLI binary not found at dist/zeit/zeit. It will not be bundled in the app."
        echo "Run without --skip-cli to bundle the CLI."
    fi

    # Temporarily hide pyproject.toml (py2app conflicts with it)
    cleanup_pyproject() {
        if [ -f pyproject.toml.bak ]; then
            echo "Restoring pyproject.toml..."
            mv pyproject.toml.bak pyproject.toml
        fi
    }
    trap cleanup_pyproject EXIT

    if [ -f pyproject.toml ]; then
        mv pyproject.toml pyproject.toml.bak
    fi

    # Clean previous build
    rm -rf build/Zeit dist/Zeit.app

    # Build with appropriate mode
    if [ "$LOCAL_APP" = true ]; then
        uv run python setup.py py2app -A
        echo "Code signing for local development..."
        codesign --force --deep --sign - dist/Zeit.app
    else
        uv run python setup.py py2app

        # Clear quarantine attributes
        echo "Clearing quarantine attributes..."
        xattr -cr dist/Zeit.app

        # Code sign the app
        if [ "$SIGN" = true ]; then
            echo "Code signing app with Developer ID..."
            codesign --force --deep --options runtime \
                --sign "$DEVELOPER_ID" \
                --entitlements entitlements.plist \
                dist/Zeit.app
        else
            echo "Code signing app (ad-hoc)..."
            codesign --force --deep --sign - dist/Zeit.app
        fi
    fi

    # Restore pyproject.toml
    cleanup_pyproject
    trap - EXIT

    echo "Menubar app built: dist/Zeit.app"
fi

# Notarize if requested
if [ "$NOTARIZE" = true ] && [ "$SKIP_APP" = false ]; then
    echo ""
    echo "Notarizing app..."
    echo "----------------------------------------"

    # Create zip for notarization
    echo "Creating zip for notarization..."
    ditto -c -k --keepParent dist/Zeit.app dist/Zeit.zip

    # Submit for notarization
    echo "Submitting to Apple (this may take a few minutes)..."
    xcrun notarytool submit dist/Zeit.zip \
        --keychain-profile "$NOTARIZE_PROFILE" \
        --wait

    # Staple the ticket
    echo "Stapling notarization ticket..."
    xcrun stapler staple dist/Zeit.app

    # Clean up zip
    rm dist/Zeit.zip

    # Verify
    echo "Verifying notarization..."
    spctl -a -v dist/Zeit.app

    echo "Notarization complete!"
fi

# Create DMG if requested
if [ "$CREATE_DMG" = true ] && [ "$SKIP_APP" = false ]; then
    echo ""
    echo "Creating DMG installer..."
    echo "----------------------------------------"

    # Get version from pyproject.toml
    VERSION=$(grep 'version = ' pyproject.toml.bak 2>/dev/null || grep 'version = ' pyproject.toml | head -1 | cut -d'"' -f2)
    ./scripts/create_dmg.sh "$VERSION" dist/Zeit.app
fi

echo ""
echo "================================================"
echo "Build complete!"
echo "================================================"
echo ""
echo "Outputs:"
[ "$SKIP_APP" = false ] && echo "  - Menubar app: dist/Zeit.app"
[ "$SKIP_CLI" = false ] && echo "  - CLI binary:  dist/zeit/zeit"
[ "$CREATE_DMG" = true ] && [ "$SKIP_APP" = false ] && echo "  - DMG installer: dist/Zeit-*.dmg"
echo ""

# Optional installation
if [ "$INSTALL" = true ]; then
    echo "Installing..."

    if [ "$SKIP_APP" = true ]; then
        echo "Error: Cannot install without app (CLI is bundled inside)"
        exit 1
    fi

    # Install app to /Applications and create CLI symlink
    uv run python scripts/install.py install --app dist/Zeit.app --to-applications
fi
