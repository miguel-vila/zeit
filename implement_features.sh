#!/usr/bin/env bash
set -euo pipefail

FEATURES_FILE="$(cd "$(dirname "$0")" && pwd)/features.json"
LOG_DIR="$(cd "$(dirname "$0")" && pwd)/implementation-logs"
mkdir -p "$LOG_DIR"

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required. Install with: brew install jq"
  exit 1
fi

if ! command -v claude &>/dev/null; then
  echo "Error: claude CLI is required."
  exit 1
fi

if [ ! -f "$FEATURES_FILE" ]; then
  echo "Error: $FEATURES_FILE not found"
  exit 1
fi

total=$(jq 'length' "$FEATURES_FILE")
echo "=== Zeit Feature Implementation ==="
echo "Found $total features in $FEATURES_FILE"
echo ""

idx=0
while [ "$idx" -lt "$total" ]; do
  implemented=$(jq -r ".[$idx].implemented" "$FEATURES_FILE")
  failed=$(jq -r ".[$idx].failedImplementation // false" "$FEATURES_FILE")
  id=$(jq -r ".[$idx].id" "$FEATURES_FILE")

  if [ "$implemented" = "true" ] || [ "$failed" != "false" ]; then
    idx=$((idx + 1))
    continue
  fi

  # Found the next unimplemented feature
  description=$(jq -r ".[$idx].description" "$FEATURES_FILE")
  python_equiv=$(jq -r '.['$idx'].pythonEquivalent | join(", ")' "$FEATURES_FILE")

  echo "────────────────────────────────────────"
  echo "[$((idx + 1))/$total] Implementing: $id"
  echo "────────────────────────────────────────"
  echo "Description: $description"
  echo "Python reference: $python_equiv"
  echo ""

  prompt="You are implementing the Swift version of a feature that is present in the Python implementation of the Zeit app. The feature is: $description . You can find some python reference code at $python_equiv . The Swift code lives under ZeitApp/Sources/ZeitApp/. Read the relevant Python files first, then read the relevant Swift files to understand the existing patterns, and implement the feature in Swift following the existing Swift conventions. Make sure the code compiles by checking existing types, imports, and patterns. Commit your changes. Only return either <DONE> or an error/description of why it wasn't possible."

  log_file="$LOG_DIR/${id}.log"
  echo "Running claude... (log: $log_file)"

  set +e
  output=$(claude --dangerously-skip-permissions -p "$prompt" 2>"$log_file")
  exit_code=$?
  echo "$output" >> "$log_file"
  set -e

  if [ $exit_code -ne 0 ]; then
    echo "FAILED: claude exited with code $exit_code"
    jq ".[$idx].failedImplementation = true | .[$idx].failureOutput = $(echo "$output" | tail -20 | jq -Rs .)" \
      "$FEATURES_FILE" > "${FEATURES_FILE}.tmp" && mv "${FEATURES_FILE}.tmp" "$FEATURES_FILE"
    idx=$((idx + 1))
    continue
  fi

  # Check if output contains <DONE>
  if echo "$output" | grep -q '<DONE>'; then
    echo "SUCCESS: $id implemented"
    jq ".[$idx].implemented = true" "$FEATURES_FILE" > "${FEATURES_FILE}.tmp" \
      && mv "${FEATURES_FILE}.tmp" "$FEATURES_FILE"
  else
    echo "FAILED: $id - claude did not return <DONE>"
    jq ".[$idx].failedImplementation = true | .[$idx].failureOutput = $(echo "$output" | tail -40 | jq -Rs .)" \
      "$FEATURES_FILE" > "${FEATURES_FILE}.tmp" && mv "${FEATURES_FILE}.tmp" "$FEATURES_FILE"
  fi

  echo ""
  idx=$((idx + 1))
done

echo "=== Summary ==="
implemented_count=$(jq '[.[] | select(.implemented == true)] | length' "$FEATURES_FILE")
failed_count=$(jq '[.[] | select(.failedImplementation == true)] | length' "$FEATURES_FILE")
remaining=$((total - implemented_count - failed_count))
echo "Implemented: $implemented_count / $total"
echo "Failed:      $failed_count / $total"
echo "Remaining:   $remaining / $total"
echo "Logs at:     $LOG_DIR/"
