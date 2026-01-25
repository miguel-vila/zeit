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

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-cli) SKIP_CLI=true; shift ;;
        --skip-app) SKIP_APP=true; shift ;;
        --skip-checks) SKIP_CHECKS=true; shift ;;
        --install) INSTALL=true; shift ;;
        --local) LOCAL_APP=true; shift ;;
        --dmg) CREATE_DMG=true; shift ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-cli      Skip building CLI binary"
            echo "  --skip-app      Skip building menubar app"
            echo "  --skip-checks   Skip code quality checks"
            echo "  --install       Install after building"
            echo "  --local         Build menubar app in alias mode (for development)"
            echo "  --dmg           Create DMG installer after building app"
            echo "  -h, --help      Show this help message"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

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

# Build menubar app with py2app
if [ "$SKIP_APP" = false ]; then
    echo ""
    if [ "$LOCAL_APP" = true ]; then
        echo "Building menubar app (py2app - alias/development mode)..."
    else
        echo "Building menubar app (py2app - distribution mode)..."
    fi
    echo "----------------------------------------"

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
    fi

    # Restore pyproject.toml
    cleanup_pyproject
    trap - EXIT

    echo "Menubar app built: dist/Zeit.app"
fi

# Build CLI with PyInstaller
if [ "$SKIP_CLI" = false ]; then
    echo ""
    echo "Building CLI (PyInstaller)..."
    echo "----------------------------------------"

    # Clean previous build
    rm -rf build/zeit_cli dist/zeit

    # Run PyInstaller
    uv run pyinstaller zeit_cli.spec --noconfirm

    # Code sign
    echo "Code signing CLI..."
    codesign --force --sign - dist/zeit

    echo "CLI built: dist/zeit"
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
[ "$SKIP_CLI" = false ] && echo "  - CLI binary:  dist/zeit"
[ "$CREATE_DMG" = true ] && [ "$SKIP_APP" = false ] && echo "  - DMG installer: dist/Zeit-*.dmg"
echo ""

# Optional installation
if [ "$INSTALL" = true ]; then
    echo "Installing..."

    INSTALL_ARGS=""
    [ "$SKIP_CLI" = false ] && INSTALL_ARGS="$INSTALL_ARGS --cli dist/zeit"
    [ "$SKIP_APP" = false ] && INSTALL_ARGS="$INSTALL_ARGS --app dist/Zeit.app"

    if [ -n "$INSTALL_ARGS" ]; then
        uv run python scripts/install.py install $INSTALL_ARGS
    else
        echo "Nothing to install (both --skip-cli and --skip-app specified)"
    fi
fi
