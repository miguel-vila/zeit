#!/usr/bin/env bash
set -euo pipefail

# Collects all features ever marked as implemented in features.json across git history.
# Outputs to docs/implemented-features.json, ordered by implementation date (oldest first).

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$REPO_ROOT/docs"
OUTPUT_FILE="$OUTPUT_DIR/implemented-features.json"

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required. Install with: brew install jq"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

# Get all commits that touched features.json, oldest first
commits=$(git -C "$REPO_ROOT" log --format="%H" --reverse -- features.json)

# Track which features we've already seen as implemented (by id)
declare -A seen_ids

# Accumulate results as a JSON array
result="[]"

for commit in $commits; do
  date=$(git -C "$REPO_ROOT" log -1 --format="%aI" "$commit")
  commit_short=$(git -C "$REPO_ROOT" log -1 --format="%h" "$commit")
  commit_msg=$(git -C "$REPO_ROOT" log -1 --format="%s" "$commit")

  # Get the blob hash for features.json at this commit
  blob=$(git -C "$REPO_ROOT" rev-parse "$commit:features.json" 2>/dev/null) || continue
  content=$(git -C "$REPO_ROOT" cat-file -p "$blob" 2>/dev/null) || continue

  # Extract all features marked as implemented in this version
  ids=$(echo "$content" | jq -r '.[] | select(.implemented == true) | .id' 2>/dev/null) || continue

  for id in $ids; do
    if [[ -z "${seen_ids[$id]:-}" ]]; then
      seen_ids[$id]=1
      # Extract the full feature object and augment with implementation metadata
      feature=$(echo "$content" | jq --arg id "$id" --arg date "$date" --arg commit "$commit_short" --arg msg "$commit_msg" \
        '.[] | select(.id == $id) | {id, description} + {implemented_at: $date, commit: $commit, commit_message: $msg}')
      result=$(echo "$result" | jq --argjson feat "$feature" '. + [$feat]')
    fi
  done
done

echo "$result" | jq '.' > "$OUTPUT_FILE"

count=$(echo "$result" | jq 'length')
echo "Collected $count implemented features → $OUTPUT_FILE"
