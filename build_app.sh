#!/bin/bash
set -e  # Exit on error

# Parse arguments
LOCAL_BUILD=false
if [ "$1" == "--local" ]; then
    LOCAL_BUILD=true
    echo "🏠 Building in local/alias mode..."
else
    echo "📦 Building for distribution..."
fi

echo "🔄 Syncing dependencies..."
uv sync

echo "📦 Preparing for build..."
# Use trap to ensure pyproject.toml is restored even if build fails
cleanup() {
    if [ -f pyproject.toml.bak ]; then
        echo "🔄 Restoring pyproject.toml..."
        mv pyproject.toml.bak pyproject.toml
        echo "✅ pyproject.toml restored"
    fi
}
trap cleanup EXIT

# Temporarily hide pyproject.toml
if [ -f pyproject.toml ]; then
    mv pyproject.toml pyproject.toml.bak
fi

# Build with appropriate mode
if [ "$LOCAL_BUILD" = true ]; then
    echo "🏗️  Building app with py2app (alias mode)..."
    uv run python setup.py py2app -A

    echo "🔏 Code signing for local development..."
    codesign --force --deep --sign - dist/Zeit.app
else
    echo "🏗️  Building app with py2app..."
    uv run python setup.py py2app
fi

echo "✅ Build complete! App is at: dist/Zeit.app"
