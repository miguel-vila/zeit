# Zeit Product Specs

Zeit is a macOS activity tracker that runs in the background, periodically capturing screenshots and using on-device AI models to classify what the user is doing. It stores activity data locally in SQLite and surfaces it through a menubar app and a CLI.

## Core Value

Automatic, private, on-device activity tracking. No data leaves the machine (when using the default MLX provider). The user gets a breakdown of how they spend their time during work hours without any manual logging.

## Features

### Activity Tracking
- Captures screenshots from all connected monitors every 60 seconds
- Detects which screen has focus and which app is frontmost
- Runs a two-stage LLM pipeline: vision model describes the screenshot, text model classifies the activity
- Supports customizable activity categories (work and personal)
- Auto-detects idle state via IOKit (skips capture when idle)
- Respects configured work hours and work days

### Menubar App
- Persistent menu bar presence with dynamic status icon
- Shows today's work/personal percentage and activity breakdown
- Day objectives management (main + 2 secondary)
- Quick actions: pause/resume tracking, view details, force track (debug mode)
- Settings: permissions, models, work hours, activity types, debug mode

### Onboarding
- Required first-run flow: permissions, model download, activity type configuration, work hours
- Same settings are editable later from the menubar settings

### CLI
- View activities by day, generate AI summaries, manage objectives
- Activity statistics with optional JSON output
- Database management (info, delete by day)
- Service management (install/uninstall/start/stop LaunchAgents)
- System diagnostics (`zeit doctor`)
- Configure work hours and activity types

### AI Models
- Default: MLX on-device inference on Apple Silicon (fully private)
- Alternative: OpenAI API for remote inference
- Configurable vision and text model names

### Scheduling
- Two LaunchAgents: one for periodic tracking, one for menubar app at login
- Tracking pauses outside work hours and on non-work days
- Manual pause/resume via stop flag file

## Specs

- [Onboarding](onboarding.md) - First-run setup flow
- [Menubar](menubar.md) - Menubar app features and settings
- [Recurring Tracking](recurring-tracking.md) - The tracking pipeline and its configuration
- [CLI](cli.md) - Command-line interface reference
- [Day Summarization](day-summarization.md) - AI-generated daily activity summaries
- [Custom Activity Types](../../large-features-specs/custom-activity-types.md) - User-configurable activity categories
