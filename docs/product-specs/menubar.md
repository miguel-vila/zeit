# Menubar App

The menubar app is the primary GUI. It lives in the macOS menu bar as a status item and shows a popover when clicked.

## Status Bar Icon

The icon is dynamically rendered and changes based on tracking state:

- **Active (during work hours):** Work percentage number with a green dot (e.g. "72%")
- **Paused manually:** Work percentage with an orange dot
- **Before work hours:** Sun icon
- **After work hours:** Work percentage with a moon symbol

## Popover Layout

The popover (300x400px) contains these sections from top to bottom:

### Header
- Today's date
- Tracking status indicator (active / paused / before hours / after hours)

### Objectives
- Shown if day objectives are set
- Displays main objective and secondary objectives

### Stats
- Work percentage for the day
- Activity breakdown by category with counts

### Actions
- **Stop Tracking / Resume Tracking** - toggles the `.zeit_stop` flag file
- **Refresh** - manually refreshes data
- **View Details** - opens a floating panel with full activity breakdown
- **Set Day Objectives** - opens a floating panel to set/edit day objectives

### Debug Section (conditional)
Only visible when debug mode is enabled:
- **Force Track** - triggers an immediate tracking capture regardless of work hours or stop flag
- **Clear Today's Data** - deletes all activities for today

### Settings
- **Launch at Login** toggle - controls the menubar LaunchAgent
- **Settings** - opens the settings panel

### Footer
- **Quit** button

## Floating Panels

Three floating panels can be opened from the menubar:

### Details Panel
Shows a detailed activity summary for today: full activity list with timestamps and breakdown chart.

### Objectives Panel
Text fields for setting day objectives:
- Main objective (required)
- Two optional secondary objectives

Saves to the database on confirmation. Objectives are included in AI day summaries.

### Settings Panel
A `NavigationSplitView` with 6 tabs:

| Tab | Content |
|-----|---------|
| **Permissions** | Read-only status of Screen Recording and Accessibility permissions |
| **Models** | Download status for each AI model (vision + text) |
| **Work Hours** | Start/end time pickers, work day toggles |
| **Activity Types** | Full editor for work and personal activity categories |
| **Debug** | Debug mode toggle |
| **About** | App version and information |

All settings tabs mirror what was configured during onboarding and can be changed at any time.

## Data Refresh

The menubar refreshes its data (stats, objectives, tracking state) every 60 seconds via a timer. This keeps the displayed information in sync with the background tracker.
