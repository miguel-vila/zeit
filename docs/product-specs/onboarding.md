# Onboarding

The onboarding flow is a required 4-step wizard shown on first launch. It cannot be skipped. Each step configures a part of the system that is also editable later from the menubar settings.

## Flow

The onboarding is presented as a floating `NSPanel` managed by `ZeitAppDelegate`. It is triggered automatically when:

- Screen Recording or Accessibility permissions are not granted, OR
- Required AI models are not downloaded

## Steps

### Step 1: Permissions

Requests two macOS permissions required for the app to function:

- **Screen Recording** - needed to capture screenshots via CoreGraphics
- **Accessibility** - needed for AppleScript to detect the active window and frontmost app

Each permission shows a status indicator (granted/not granted) and a button to open the relevant System Settings pane. The step polls permissions every 5 seconds and also re-checks when the app regains focus (after the user returns from System Settings).

The user can continue once both permissions are granted.

**Later:** Viewable in Settings > Permissions tab (read-only status display).

### Step 2: Model Download

Downloads the AI models needed for activity identification:

- **Vision model** (e.g. `qwen3-vl:4b`) - describes what's on screen
- **Text model** (e.g. `qwen3:8b`) - classifies the description into an activity

Each model shows download progress with a progress bar. Models are downloaded sequentially to avoid memory pressure. Models that are already downloaded show a checkmark.

The user can continue once all models are downloaded.

**Later:** Download status viewable in Settings > Models tab.

### Step 3: Activity Types

Configure the activity categories that the tracker uses for classification. Types are split into two groups:

- **Work activities** - e.g. Slack, Work Coding, Zoom Meeting
- **Personal activities** - e.g. Social Media, YouTube, Personal Email

Each type has a name and a description (the description is included in the LLM prompt to guide classification). The user can add, edit, reorder, and delete types. There are sensible defaults pre-populated.

Validation rules:
- At least 1 work type and 1 personal type required
- Maximum 30 total types (to stay within LLM token limits)
- Names: 1-50 characters, must be unique
- Descriptions: 1-200 characters
- "idle" is a reserved name

The user can reset to defaults at any time.

**Later:** Fully editable in Settings > Activity Types tab, or via `zeit set-activity-types` CLI command.

### Step 4: Work Hours & Other Settings

Configure when tracking should be active:

- **Start time** and **end time** (hour and minute pickers)
- **Work days** (toggle each day of the week)

Defaults: 9:00-17:30, Monday through Friday.

**Later:** Editable in Settings > Work Hours tab, or via `zeit set-work-hours` CLI command.

## Completion

When the user finishes all 4 steps, the onboarding panel closes and the app:

1. Installs the LaunchAgent services (tracker + menubar)
2. Begins the normal menubar operation with periodic data refresh
