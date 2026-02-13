# CLAUDE.md

**Updated:** 2026-02-12 | **Branch:** main

## Overview

macOS activity tracker: periodic screenshots → LLM vision model → activity classification → SQLite storage. Single Swift executable runs as both menubar app (GUI) and CLI. Scheduled via launchd.

## Tech Stack

- Swift 5.9+ / Swift Package Manager
- macOS 14 (Sonoma) minimum
- SwiftUI + Composable Architecture (TCA) for UI
- ArgumentParser (CLI framework)
- GRDB (SQLite database)
- Yams (YAML config)
- MLX Swift (on-device inference on Apple Silicon)
- Ollama / OpenAI (alternative LLM providers)
- Hugging Face Hub (model downloads)

## Structure

```
Sources/ZeitApp/
├── main.swift                     # Entry point: CLI vs GUI mode dispatcher
├── App/
│   └── ZeitApp.swift              # SwiftUI App + AppDelegate (menubar setup)
├── CLI/                           # Command-line interface
│   ├── ZeitCLI.swift              # Root CLI command router
│   ├── TrackCommand.swift         # Single tracking capture
│   ├── ViewCommand.swift          # Activity history (7 subcommands)
│   ├── StatsCommand.swift         # Activity statistics
│   ├── DBCommand.swift            # Database management
│   ├── ServiceCommand.swift       # LaunchAgent management (6 subcommands)
│   ├── DoctorCommand.swift        # Diagnostics
│   └── DatabaseHelper.swift       # Database access wrapper
├── Clients/                       # Dependency-injected service interfaces
│   ├── DatabaseClient.swift       # Read/write activities & objectives
│   ├── TrackingClient.swift       # Tracking state management
│   ├── LaunchAgentClient.swift    # Service install/unload
│   ├── ModelClient.swift          # LLM model management
│   ├── NotificationClient.swift   # macOS notifications
│   └── PermissionsClient.swift    # Screen recording & AppleScript permissions
├── Core/                          # Core functionality
│   ├── ZeitConfig.swift           # YAML config loader
│   ├── ScreenCapture.swift        # Multi-monitor capture (CoreGraphics)
│   ├── ActiveWindow.swift         # Active window detection (AppleScript)
│   ├── IdleDetection.swift        # IOKit idle time check
│   ├── Permissions.swift          # Permission checking & requests
│   └── FloatingPanel.swift        # UI utilities
├── LLM/                           # LLM integration
│   ├── LLMProvider.swift          # Protocol for text + vision providers
│   ├── ActivityIdentifier.swift   # Screenshot → description → classification
│   ├── DaySummarizer.swift        # Activity grouping → summary generation
│   ├── OllamaClient.swift         # Local Ollama HTTP API client
│   ├── MLXClient.swift            # On-device MLX inference
│   ├── MLXModelManager.swift      # MLX model loading & management
│   ├── OpenAIClient.swift         # OpenAI API integration
│   └── Prompts.swift              # Prompt templates
├── Models/                        # Data structures
│   ├── Activity.swift             # Activity enum + ActivityEntry + DayRecord
│   ├── ActivityStat.swift         # Statistics breakdown
│   ├── ActivitySummarization.swift # Day summary grouping
│   └── TrackingState.swift        # Menubar state machine
└── Features/                      # SwiftUI features (TCA reducers)
    ├── Menubar/                   # Main menubar popover
    ├── Details/                   # Detailed activity view
    ├── Objectives/                # Day objectives
    ├── Onboarding/                # First-run setup flow
    ├── Permissions/               # Permission request UI
    ├── ModelDownload/             # Model download progress
    ├── Setup/                     # Setup configuration
    └── OtherSettings/             # Debug mode toggle
```

## Single Binary, Dual Mode

The same `ZeitApp` executable handles both GUI and CLI:

- **No args** (or Finder launch with `-psn`): starts menubar app
- **With args**: executes CLI command

```bash
# GUI mode
open dist/Zeit.app
./dist/Zeit.app/Contents/MacOS/ZeitApp

# CLI mode
./dist/Zeit.app/Contents/MacOS/ZeitApp view today
./dist/Zeit.app/Contents/MacOS/ZeitApp track --force
```

## CLI Commands

```bash
zeit version                         # Show version
zeit track [--delay N] [--force]     # Single tracking capture
zeit doctor                          # Diagnostics

# View activities
zeit view today                      # Today's activities
zeit view yesterday                  # Yesterday's activities
zeit view all                        # All days summary
zeit view day <YYYY-MM-DD>           # Specific day
zeit view summarize [date] [-m MODEL] # AI day summary
zeit view objectives [date]          # View day objectives
zeit view set-objectives --main "..." [--opt1 "..."] [--opt2 "..."] [date]
zeit view delete-objectives <date> [--force]

# Statistics
zeit stats [date]                    # Activity statistics

# Database management
zeit db info                         # Database stats
zeit db delete-today                 # Delete today's data
zeit db delete-day <date>            # Delete specific day
zeit db delete-objectives <date>     # Delete objectives

# Service management
zeit service status                  # Check LaunchAgent status
zeit service start                   # Resume tracking
zeit service stop                    # Pause tracking
zeit service install [--cli PATH] [--app PATH]
zeit service uninstall               # Remove LaunchAgents
zeit service restart                 # Restart tracker
```

## Database Schema

```sql
-- ~/.local/share/zeit/zeit.db (GRDB/SQLite)

CREATE TABLE daily_activities (
    date TEXT PRIMARY KEY,           -- YYYY-MM-DD
    activities TEXT NOT NULL,        -- JSON array of ActivityEntry
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE day_objectives (
    date TEXT PRIMARY KEY,           -- YYYY-MM-DD
    main_objective TEXT NOT NULL,
    secondary_objectives TEXT,       -- JSON array of strings (max 2)
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
```

## Build & Installation

```bash
# Debug build
./build.sh

# Release build and install to /Applications
./build.sh --release --install

# Signed release with DMG
./build.sh --release --sign --dmg

# All options
./build.sh --release      # Optimized build
./build.sh --install      # Install to /Applications
./build.sh --sign         # Code sign (requires DEVELOPER_ID env var)
./build.sh --notarize     # Notarize with Apple (requires NOTARIZE_PROFILE env var)
./build.sh --dmg          # Create DMG installer
./build.sh --clean        # Clean build artifacts first
```

Output: `dist/Zeit.app` (macOS app bundle)

## Where to Look

| Task | Location |
|------|----------|
| Add CLI command | `Sources/ZeitApp/CLI/` (ZeitCLI.swift routes to subcommands) |
| Add activity category | `Sources/ZeitApp/Models/Activity.swift` → Activity enum |
| Modify LLM prompts | `Sources/ZeitApp/LLM/Prompts.swift` |
| Change screenshot behavior | `Sources/ZeitApp/Core/ScreenCapture.swift` |
| Modify idle detection | `Sources/ZeitApp/Core/IdleDetection.swift` |
| Add menubar features | `Sources/ZeitApp/Features/Menubar/` (MenubarFeature + MenubarView) |
| Add new UI feature | `Sources/ZeitApp/Features/` (TCA reducer + SwiftUI view) |
| Add dependency client | `Sources/ZeitApp/Clients/` (use @DependencyClient) |
| Change database schema | `Sources/ZeitApp/Clients/DatabaseClient.swift` |
| Modify work hours | `~/.local/share/zeit/conf.yml` |
| Change data paths | `Sources/ZeitApp/Core/ZeitConfig.swift` |
| Add LLM provider | `Sources/ZeitApp/LLM/` (conform to LLMProvider/VisionLLMProvider) |
| Modify build process | `build.sh` |

## LLM Providers

Three provider options configured via `conf.yml`:

| Provider | Description | Config |
|----------|-------------|--------|
| **MLX** (default) | On-device Apple Silicon inference | `provider: 'mlx'` |
| **Ollama** | Local HTTP API (localhost:11434) | `provider: 'ollama'` |
| **OpenAI** | Remote API (requires `OPENAI_API_KEY`) | `provider: 'openai'` |

**Vision pipeline**: screenshots → vision model (e.g. `qwen3-vl:4b`) → text description → text model (e.g. `qwen3:8b`) → activity classification (JSON)

## Activity Categories

**Personal**: personal_browsing, social_media, youtube_entertainment, personal_email, personal_ai_use, personal_finances, professional_development, online_shopping, personal_calendar, entertainment

**Work**: slack, work_email, zoom_meeting, work_coding, work_browsing, work_calendar

**System**: idle (auto-detected via IOKit)

## Data Directory

All runtime data in `~/.local/share/zeit/`:

| File | Purpose |
|------|---------|
| `conf.yml` | User config (created with defaults on first run) |
| `zeit.db` | SQLite database with activities and objectives |
| `.zeit_stop` | Flag file to pause tracking |

## Configuration

```yaml
# ~/.local/share/zeit/conf.yml
work_hours:
  start_hour: 9
  end_hour: 18

models:
  vision: 'qwen3-vl:4b'
  text:
    provider: 'mlx'     # 'mlx' (on-device), 'ollama', or 'openai'
    model: 'qwen3:8b'   # e.g., 'gpt-4o-mini' for openai
```

| File | Purpose |
|------|---------|
| `~/.local/share/zeit/conf.yml` | User config: work hours, model names, provider |
| `Package.swift` | SPM dependencies and targets |
| `ZeitApp.entitlements` | macOS permissions (sandbox disabled) |
| `.env` | Runtime env vars |

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `IDLE_THRESHOLD_SECONDS` | 300 | Seconds before marking as idle |
| `OPENAI_API_KEY` | — | Required when using OpenAI provider |
| `DEVELOPER_ID` | — | Code signing certificate name |
| `NOTARIZE_PROFILE` | — | Keychain profile for notarization |

## Commands

```bash
# Development
swift build                           # Build
swift test                            # Run tests
swift run ZeitApp --help              # CLI help
swift run ZeitApp view today          # View today's activities

# Build for distribution
./build.sh --release --install        # Release build + install
```

## Code Conventions

- Swift concurrency: async/await throughout, Sendable types
- TCA (Composable Architecture) for all UI features (reducer + view pairs)
- @DependencyClient for testable service interfaces
- Actor-based database access (thread-safe GRDB)
- Protocol-based LLM providers (LLMProvider, VisionLLMProvider)
- Modern SwiftUI patterns (@State, @Binding, ViewStore)

## Design Decisions

### Single Executable

One binary serves both CLI and GUI. `main.swift` checks `CommandLine.arguments` to decide which mode to run. Avoids maintaining two separate build targets.

### MLX as Default Provider

MLX runs models natively on Apple Silicon — no Ollama server required. Falls back to Ollama for vision if MLX client unavailable.

### GRDB Over Core Data

Direct SQLite access with async support. Simpler than Core Data for this use case.

### TCA Architecture

All UI features use Composable Architecture reducers. Provides testable state management, dependency injection, and predictable side effects.

### No Sandbox

App requires full filesystem access (data dir, LaunchAgents, logs) and AppleScript execution, so sandboxing is disabled.

## Services & Scheduling

Two LaunchAgents installed to `~/Library/LaunchAgents/`:

| Agent | Label | Purpose |
|-------|-------|---------|
| Tracker | `co.invariante.zeit` | Runs `zeit track` every 60s during work hours |
| Menubar | `co.invariante.zeit.menubar` | Launches Zeit.app at login |

## Notes

- **Multi-monitor**: Captures all screens via CoreGraphics, detects active screen
- **Permissions**: Requires Screen Recording + Automation (AppleScript)
- **Onboarding**: Required flow — permissions, model download, setup (no skip)
- **Debug mode**: Toggle in settings, enables "Force Track" button in menubar
- **LaunchAgents**: Installed to ~/Library/LaunchAgents/
- **Logs**: Written to ~/Library/Logs/zeit/
