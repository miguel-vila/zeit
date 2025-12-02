#!/bin/bash

# Wrapper script for zeit activity tracker
# This script is called by launchd to capture activity

# Change to project directory first
cd "/Users/miguelvilagonzalez/repos/zeit" || exit 1

# Activate virtual environment
source .venv/bin/activate || exit 1

# Use Python to check work hours (reads from conf.yml)
python -c "
from config import is_within_work_hours
import sys
sys.exit(0 if is_within_work_hours() else 1)
"

# Exit early if outside work hours
if [ $? -ne 0 ]; then
    # Outside work hours
    exit 0
fi

# Check if manual stop flag is set
STOP_FLAG="$HOME/.zeit_stop"
if [ -f "$STOP_FLAG" ]; then
    # User has manually stopped tracking
    exit 0
fi

# Run the tracker
python main.py

# Exit with the Python script's exit code
exit $?
