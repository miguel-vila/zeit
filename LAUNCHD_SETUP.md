# Launchd Setup for Zeit Activity Tracker

This guide explains how to set up the zeit activity tracker to run automatically every minute during work hours using macOS launchd.

## Overview

- **Runs every**: 60 seconds
- **Work hours**: Monday-Friday, 9am-5pm (configurable in `run_tracker.sh`)
- **Logs**: Stored in `logs/launchd.out.log` and `logs/launchd.err.log`
- **Database**: `data/zeit.db`

## Prerequisites

1. **Screen Recording Permission**: On macOS, the process needs permission to capture screenshots
   - You'll need to grant permission to the process running the script
   - This is typically handled when you first run the script manually

2. **Virtual Environment**: Ensure your Python virtual environment is set up
   ```bash
   python -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt  # if you have one
   ```

## Installation Steps

### 1. Copy the plist to LaunchAgents directory

```bash
cp co.invariante.zeit.plist ~/Library/LaunchAgents/
```

### 2. Load the launch agent

```bash
launchctl load ~/Library/LaunchAgents/co.invariante.zeit.plist
```

### 3. Start the service (optional, it will start on next login if you don't)

```bash
launchctl start co.invariante.zeit
```

## Managing the Service

### Check if the service is running

```bash
launchctl list | grep co.invariante.zeit
```

### View recent logs

```bash
# Standard output
tail -f logs/launchd.out.log

# Errors
tail -f logs/launchd.err.log

# Application logs
tail -f logs/zeit.log
```

### Stop the service

```bash
launchctl stop co.invariante.zeit
```

### Unload the service (disable)

```bash
launchctl unload ~/Library/LaunchAgents/co.invariante.zeit.plist
```

### Reload after making changes

```bash
launchctl unload ~/Library/LaunchAgents/co.invariante.zeit.plist
cp co.invariante.zeit.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/co.invariante.zeit.plist
```

## Configuration

### Changing Work Hours

Edit `run_tracker.sh` and modify these variables:

```bash
WORK_START_HOUR=9   # 9am
WORK_END_HOUR=18    # 6pm (18 means runs until 5:59pm)
```

### Changing the Interval

Edit `co.invariante.zeit.plist` and change the `StartInterval` value (in seconds):

```xml
<key>StartInterval</key>
<integer>60</integer>  <!-- 60 seconds = 1 minute -->
```

## Troubleshooting

### Permission Issues

If you get screen recording permission errors:
1. Go to System Settings > Privacy & Security > Screen Recording
2. Add the terminal app or the process that's running the script
3. You may need to restart the launchd service

### Service Not Running

1. Check if it's loaded:
   ```bash
   launchctl list | grep co.invariante.zeit
   ```

2. Check the error log:
   ```bash
   cat logs/launchd.err.log
   ```

3. Try running the script manually to see if it works:
   ```bash
   ./run_tracker.sh
   ```

### No Data Being Captured

1. Check the application logs:
   ```bash
   tail -n 50 logs/zeit.log
   ```

2. Verify you're within work hours (Monday-Friday, 9am-5pm)

3. Check that Ollama is running:
   ```bash
   ollama list
   ```

## Testing Before Full Deployment

### Test the wrapper script manually

```bash
./run_tracker.sh
```

### Test during off-hours

Temporarily comment out the work hours check in `run_tracker.sh`:

```bash
# if [ "$CURRENT_DAY" -gt 5 ]; then
#     exit 0
# fi
#
# if [ "$CURRENT_HOUR" -lt "$WORK_START_HOUR" ] || [ "$CURRENT_HOUR" -ge "$WORK_END_HOUR" ]; then
#     exit 0
# fi
```

### View captured data

```bash
python view_data.py today
```
