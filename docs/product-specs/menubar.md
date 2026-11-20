# Menubar App

The menubar app is the primary GUI. It lives in the macOS menu bar as a status item and shows a popover when clicked.

## Tracking Status

The menubar reports what a tracking tick would do, not what the settings say. It
reads the same gate the tracker acts on (`TrackingTick`), minus the cadence
check, so the icon and the popover cannot disagree with the tracker log or
`zeit doctor` about whether Zeit is recording.

Four states:

| State | Meaning | Icon | Status line |
|-------|---------|------|-------------|
| Tracking | A tick records now | Primary group percentage with a green dot | "Tracking active" |
| On battery | Tracking is on, every tick holds off because the machine is unplugged and `skip_on_battery` is set | Percentage with a `bolt.slash` symbol | "Paused — on battery" |
| Paused by you | The `.zeit_stop` flag exists | Percentage with an orange dot | "Paused — by you" |
| Outside the schedule | Now is outside every configured window | Percentage with a moon symbol | The schedule's own message |

A hold that clears itself inside a minute — a tick inside the configured
cadence — reads as tracking, so the indicator does not flicker every minute.

Each hold gets a symbol rather than a fourth dot colour: at 5pt, hue alone is
not a cue, and the icon is all that shows without opening the popover.

### Why the battery hold is called out

Holding off on battery is invisible from outside the tracker: the schedule is
met and the stop flag is absent, so a status built from those two alone reports
"Tracking active" through an afternoon of skipped ticks.

## Popover Layout

The popover (300x400px) contains these sections from top to bottom:

### Header
- Today's date, and the number of activities stored for it
- Tracking status indicator (see [Tracking Status](#tracking-status))
- **Age of the newest entry**, beside the status: "just now", "25m", "6h 20m".
  It turns to a warning colour once the gap is wider than three cadences, but
  only where entries were expected — a deliberate pause does not cry wolf. It
  is measured against the whole database rather than today's row, so early on a
  fresh day the gap still reaches back into yesterday.

  This is the one cue that does not depend on knowing why the tracker is quiet.
  A launchd throttle, a classification that fails every tick, a tracker that
  dies on start: none of them are modelled, and all of them widen this gap.
- **Remedy row**, only while a battery hold is on: "Plug in, or turn off Skip on
  battery". The row is the control, not just the message — it opens Settings at
  the Schedule tab, where the setting lives. The Settings row below carries a
  dot for the same reason.

### Objectives
- Shown if day objectives are set
- Displays main objective and secondary objectives

### Stats
- Work percentage for the day
- Activity breakdown by category with counts

### Actions
- **Stop Tracking / Resume Tracking** - toggles the `.zeit_stop` flag file. The
  label follows the flag, never the status: a battery hold stops the ticks
  without touching the flag, so the button still offers to set it. It is
  disabled only outside the tracking schedule, where the flag changes nothing.
- **Refresh** - manually refreshes data
- **View Details** - opens a floating panel with full activity breakdown
- **Set Day Objectives** - opens a floating panel to set/edit day objectives

### Debug Section (debug builds only)

Only present in debug builds (`#if DEBUG`), compiled out entirely in release builds:

- **Force Track** - triggers an immediate tracking capture regardless of work hours or stop flag
- **Force Track & Sample** - triggers tracking and saves sample data for LLM pipeline debugging
- **Force Track & Sample with Delay** - same as above but with a configurable delay
- **Clear Today's Data** - deletes all activities for today

### Settings
- **Launch at Login** toggle - whether the menubar LaunchAgent plist is installed. Turning it off removes the plist and leaves the running app alone; it only decides what happens at the next login.
- **Settings** - opens the settings panel

### Footer
- **Quit** button - launchd keeps the menubar app alive, so quitting first takes the job out of the login session (`launchctl bootout`) and then terminates. The plist stays, so Zeit still starts at the next login. The right-click menu's Quit goes through the same path, because terminating without stopping the job would just make launchd start Zeit again.

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
A `NavigationSplitView` with 5 tabs:

| Tab | Content |
|-----|---------|
| **Permissions** | Read-only status of Screen Recording and Accessibility permissions |
| **Models** | Download status for each AI model (vision + text) |
| **Work Hours** | Start/end time pickers, work day toggles |
| **Activity Types** | Full editor for work and personal activity categories |
| **About** | App version and information |

All settings tabs mirror what was configured during onboarding and can be changed at any time.

## Data Refresh

The menubar refreshes its data (stats, objectives, tracking state, newest entry) every 60 seconds via a timer. This keeps the displayed information in sync with the background tracker. The power source is read on that same tick, so unplugging takes up to a minute to show.
