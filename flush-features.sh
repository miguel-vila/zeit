#!/usr/bin/env bash
set -euo pipefail

# Moves implemented features from features.json to docs/implemented-features.json,
# keeping only id and description.

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
FEATURES_FILE="$REPO_ROOT/features.json"
IMPLEMENTED_FILE="$REPO_ROOT/docs/implemented-features.json"

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required. Install with: brew install jq"
  exit 1
fi

mkdir -p "$REPO_ROOT/docs"

# Initialize implemented file if it doesn't exist
if [ ! -f "$IMPLEMENTED_FILE" ]; then
  echo "[]" > "$IMPLEMENTED_FILE"
fi

# Extract implemented features (only id and description)
implemented=$(jq '[.[] | select(.implemented == true) | {id, description}]' "$FEATURES_FILE")
count=$(echo "$implemented" | jq 'length')

if [ "$count" -eq 0 ]; then
  echo "No implemented features to flush."
  exit 0
fi

# Append to implemented-features.json
existing=$(jq '.' "$IMPLEMENTED_FILE")
merged=$(echo "$existing" "$implemented" | jq -s '.[0] + .[1]')
echo "$merged" | jq '.' > "$IMPLEMENTED_FILE"

# Remove implemented features from features.json
remaining=$(jq '[.[] | select(.implemented != true)]' "$FEATURES_FILE")
echo "$remaining" | jq '.' > "$FEATURES_FILE"

echo "Flushed $count feature(s) → $IMPLEMENTED_FILE"
remaining_count=$(echo "$remaining" | jq 'length')
echo "Remaining in features.json: $remaining_count"
