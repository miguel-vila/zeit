#!/bin/bash

# Script to manually stop zeit tracking
# Creates a flag file that run_tracker.sh checks before tracking

STOP_FLAG="$HOME/.zeit_stop"

# Create the stop flag
touch "$STOP_FLAG"

echo "Zeit tracking stopped. Run 'resume_tracking.sh' to resume."
