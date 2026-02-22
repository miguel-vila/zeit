# Recurring Tracking

The core of Zeit is a tracking process that runs every 60 seconds, captures screenshots, and classifies the user's current activity using AI.

## Scheduling

A LaunchAgent (`co.invariante.zeit`) triggers `zeit track` every 60 seconds. The plist is installed to `~/Library/LaunchAgents/co.invariante.zeit.plist` with `StartInterval: 60` and `RunAtLoad: true`.

Logs are written to:
- `~/Library/Logs/zeit/tracker.out.log`
- `~/Library/Logs/zeit/tracker.err.log`

## Pipeline

Each tracking iteration runs these steps in order:

### 1. Gate Checks

Before doing any work, the tracker checks three conditions:

- **Work hours** - Is the current time within the configured start/end hours on a configured work day? Checked via `ZeitConfig`. Skips silently if outside hours.
- **Stop flag** - Does `~/.local/share/zeit/.zeit_stop` exist? If so, tracking is paused. The menubar app creates/removes this file via the pause/resume button.
- **Idle detection** - Is the system idle for longer than the threshold? Uses IOKit's `HIDIdleTime` property (default: 300 seconds, configurable via `IDLE_THRESHOLD_SECONDS` env var). If idle, records an `idle` activity entry and stops without capturing screenshots.

All three checks are bypassed when running `zeit track --force`.

### 2. Screenshot Capture

Captures all connected monitors using CoreGraphics (`CGDisplayCreateImage`):

- Iterates through `NSScreen.screens` and maps each to a display ID
- Saves PNG files to `/tmp/zeit_screenshots/` with timestamped names
- Returns a dictionary of `[screenNumber: fileURL]` (1-based screen numbers)
- Retina images are auto-downscaled to max 1280px for the LLM payload
- Temporary files are deleted after processing (kept if `--debug` flag is used)

### 3. Active Window Detection

Uses AppleScript via System Events to determine:

- **Active screen number** - which monitor has the focused window (based on window bounds and screen geometry, with coordinate system conversion between AppleScript's top-left origin and NSScreen's bottom-left origin)
- **Frontmost app name** - the name of the application that currently has focus

Both are used as hints in the vision prompt.

### 4. Vision Model (Stage 1)

The vision model receives the screenshots and produces a text description of what's on screen.

**Prompt construction** (`Prompts.visionDescription`):
- Tells the model which screen is active (for multi-monitor setups)
- Mentions the frontmost app name as a hint
- Asks for a description of the main activity, noting visual cues like mouse cursor position, focus rings, and text input carets

**Model:** Configured in `conf.yml` under `models.vision` (default: `qwen3-vl:4b`). Runs on-device via MLX Swift.

### 5. Activity Classification (Stage 2)

The text model receives the vision description and classifies it into an activity category.

**Prompt construction** (`Prompts.activityClassification`):
- Lists all configured activity types, separated by work and personal categories
- Each type includes its name and description (as configured by the user)
- Includes the vision model's description from stage 1
- Requests a structured JSON response

**Structured output schema:**
```json
{
  "main_activity": "<activity_type_id or 'idle'>",
  "reasoning": "<explanation of why this activity was chosen>",
  "secondary_context": "<optional context from non-active screens>"
}
```

The text model runs with `temperature=0` for deterministic classification.

**Model:** Configured in `conf.yml` under `models.text.model` (default: `qwen3:8b`). Provider configured under `models.text.provider` (`mlx` or `openai`).

### 6. Storage

The classified activity is saved as an `ActivityEntry`:

```swift
struct ActivityEntry {
    let timestamp: String      // ISO8601
    let activity: Activity     // e.g. Activity(rawValue: "work_coding")
    let reasoning: String?     // LLM's explanation
    let description: String?   // Vision model's description
}
```

Entries are appended to a JSON array in the `daily_activities` table, keyed by date (`YYYY-MM-DD`). If a record for today already exists, the new entry is appended; otherwise a new record is created.

## Configuration

### Work Hours

```yaml
# ~/.local/share/zeit/conf.yml
work_hours:
  start_hour: 9
  start_minute: 0
  end_hour: 17
  end_minute: 30
  work_days: ['mon', 'tue', 'wed', 'thu', 'fri']
```

Configurable via: Settings > Work Hours tab, onboarding step 4, or `zeit set-work-hours` CLI command.

### Models

```yaml
models:
  vision: 'qwen3-vl:4b'
  text:
    provider: 'mlx'
    model: 'qwen3:8b'
```

Provider options:
- `mlx` - On-device Apple Silicon inference via MLX Swift (default, fully private)
- `openai` - Remote inference via OpenAI API (requires `OPENAI_API_KEY` environment variable)

### Activity Types

Stored in the `activity_types` database table. Each type has an ID, name, description, and work/personal flag. Configurable via Settings > Activity Types tab or `zeit set-activity-types` CLI command.

The activity types directly shape the classification prompt: the LLM is given the list of types with descriptions and must pick one.

### Idle Threshold

Default: 300 seconds (5 minutes). Override via `IDLE_THRESHOLD_SECONDS` environment variable.

## Controlling the Tracker

| Action | How |
|--------|-----|
| Pause tracking | `zeit service stop` or menubar pause button (creates `.zeit_stop` flag) |
| Resume tracking | `zeit service start` or menubar resume button (removes `.zeit_stop` flag) |
| Force a single capture | `zeit track --force` or "Force Track" button in menubar (debug mode) |
| Restart the service | `zeit service restart` |
| Uninstall completely | `zeit service uninstall` |
