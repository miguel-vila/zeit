# Zeit Menu Bar App Setup

This guide explains how to set up the Zeit menu bar app that displays your activity summary in the macOS menu bar.

## Overview

The menu bar app provides:
- **Real-time summary** of today's activities in the menu bar
- **Work percentage** displayed as an icon (e.g., "📊 65%")
- **Activity breakdown** in the dropdown menu
- **Auto-refresh** every 60 seconds
- **Manual refresh** and detail view options

## Prerequisites

### 2. Verify Installation

Test the app manually before setting up auto-start:

```bash
python menubar_app.py
```

You should see a 📊 icon appear in your menu bar. Click it to see the menu.

**Note**: The first time you run it, macOS may ask for permissions. You might need to:
- Allow notifications (for the detail view feature)
- Grant accessibility permissions if needed

## Installation Steps

### 1. Copy the plist to LaunchAgents directory

```bash
cp co.invariante.zeit.menubar.plist ~/Library/LaunchAgents/
```

### 2. Load the launch agent

```bash
launchctl load ~/Library/LaunchAgents/co.invariante.zeit.menubar.plist
```

The menu bar app should now appear automatically!

### 3. Verify it's running

```bash
launchctl list | grep co.invariante.zeit.menubar
```

You should see output showing the service is loaded.

## Managing the Service

### Check if the service is running

```bash
launchctl list | grep co.invariante.zeit.menubar
```

### View logs

```bash
# Application logs
tail -f logs/menubar.log

# Standard output
tail -f logs/menubar.out.log

# Errors
tail -f logs/menubar.err.log
```

### Stop the service

```bash
launchctl stop co.invariante.zeit.menubar
```

### Unload the service (disable auto-start)

```bash
launchctl unload ~/Library/LaunchAgents/co.invariante.zeit.menubar.plist
```

### Reload after making changes

If you modify the app code or plist:

```bash
launchctl unload ~/Library/LaunchAgents/co.invariante.zeit.menubar.plist
cp co.invariante.zeit.menubar.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/co.invariante.zeit.menubar.plist
```

## Customization

### Change Update Frequency

Edit `menubar_app.py` and modify the timer decorator:

```python
@rumps.timer(60)  # Change 60 to desired seconds
def update_menu(self, _=None):
```

### Change Menu Bar Icon

Edit `menubar_app.py` and change the icon in the `__init__` method:

```python
super().__init__("📊", quit_button=None)  # Change "📊" to your preferred emoji/text
```

Or dynamically in `_update_menu_with_data`:

```python
self.title = f"📊 {work_percentage:.0f}%"
```

### Customize Activity Display

Edit the `_update_menu_with_data` method to change how activities are displayed in the menu.

## Troubleshooting

### Menu bar app doesn't appear

1. Check if it's running:
   ```bash
   launchctl list | grep co.invariante.zeit.menubar
   ```

2. Check the error logs:
   ```bash
   cat logs/menubar.err.log
   cat logs/menubar.log
   ```

3. Try running manually to see errors:
   ```bash
   cd /Users/miguelvilagonzalez/repos/zeit
   source .venv/bin/activate
   python menubar_app.py
   ```

### "No activities tracked yet" message

This is normal if:
- The tracker service hasn't run yet today
- You're outside work hours (9am-6pm, Mon-Fri)
- The database is empty

Check the tracker service:
```bash
launchctl list | grep co.invariante.zeit
```

And verify data:
```bash
python view_data.py today
```

### Menu bar icon appears but data is wrong

1. Manually refresh using the "Refresh" menu item
2. Check database integrity:
   ```bash
   python view_data.py today
   ```

3. Check logs for errors:
   ```bash
   tail -n 50 logs/menubar.log
   ```

### App crashes or disappears

The launchd service has `KeepAlive` set to `true`, so it should automatically restart. Check logs:

```bash
cat logs/menubar.err.log
```

### Notifications don't appear

macOS might have blocked notifications. Go to:
- System Settings > Notifications
- Find Python or Terminal in the list
- Enable notifications

## Running Both Services

You should have two services running:

1. **Tracker Service** (`co.invariante.zeit`) - Captures screenshots every minute during work hours
2. **Menu Bar App** (`co.invariante.zeit.menubar`) - Displays the summary in the menu bar

Check both:
```bash
launchctl list | grep co.invariante
```

You should see both services listed.

## Uninstalling

To completely remove the menu bar app:

```bash
# Unload the service
launchctl unload ~/Library/LaunchAgents/co.invariante.zeit.menubar.plist

# Remove the plist
rm ~/Library/LaunchAgents/co.invariante.zeit.menubar.plist

# (Optional) Remove the app script
# rm /Users/miguelvilagonzalez/repos/zeit/menubar_app.py
```
