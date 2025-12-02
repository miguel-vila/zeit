#!/bin/bash

# Script to resume zeit tracking
# Removes the flag file that stops tracking

STOP_FLAG="$HOME/.zeit_stop"

# Remove the stop flag if it exists
if [ -f "$STOP_FLAG" ]; then
    rm "$STOP_FLAG"
    echo "Zeit tracking resumed."
else
    echo "Tracking was not stopped. Nothing to resume."
fi
