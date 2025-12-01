#!/bin/bash

# Wrapper script for zeit activity tracker
# This script is called by launchd to capture activity

# Work hours configuration
WORK_START_HOUR=9   # 9am
WORK_END_HOUR=18    # 6pm (exclusive, so 9-17 means 9am-5:59pm)

# Check if we're in work hours (Monday-Friday, 9am-6pm)
CURRENT_HOUR=$(date +%H)
CURRENT_DAY=$(date +%u)  # 1=Monday, 7=Sunday

Exit early if outside work hours
if [ "$CURRENT_DAY" -gt 5 ]; then
    # Weekend (Saturday=6, Sunday=7)
    exit 0
fi

if [ "$CURRENT_HOUR" -lt "$WORK_START_HOUR" ] || [ "$CURRENT_HOUR" -ge "$WORK_END_HOUR" ]; then
    # Outside work hours
    exit 0
fi

# Change to project directory
cd "/Users/miguelvilagonzalez/repos/zeit" || exit 1

# Activate virtual environment
source .venv/bin/activate || exit 1

# Run the tracker
python main.py

# Exit with the Python script's exit code
exit $?
