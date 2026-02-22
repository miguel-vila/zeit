#!/usr/bin/env bash
# Verify (and optionally fix) documentation against the codebase.
# Forwards all arguments to the TypeScript entry point via tsx.
#
# Usage: ./scripts/verify-docs-in-sync-with-code.sh [options] [repo_dir]
#   Run with --help for details.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/verify-docs-in-sync-with-code"

# Default repo_dir to the repo root (one level above scripts/)
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

npx --prefix "$PROJECT_DIR" tsx "$PROJECT_DIR/src/index.ts" "$@"
