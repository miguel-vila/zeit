#!/usr/bin/env bash
# Check markdown links using mlc (markup link checker)
# Used by both the pre-commit hook and CI

set -euo pipefail

if ! command -v mlc &> /dev/null; then
    echo "Error: mlc (markup link checker) is not installed."
    echo "Install it with: brew install mlc"
    exit 1
fi

echo "Checking markdown links..."
mlc --offline --ignore-path .build,*/node_modules/ .
