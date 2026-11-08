# Architecture

Zeit is a macOS activity tracker composed of four main components that share a common data layer. This document describes each component, the patterns they use, and how they connect.

## Components

### 1. Menubar App (GUI)

A SwiftUI application that lives in the macOS menu bar. Built entirely with **The Composable Architecture (TCA)**.

**Entry point:** `Sources/ZeitApp/App/ZeitApp.swift`
**Features:** `Sources/ZeitApp/Features/`

The app is managed by `ZeitAppDelegate`, which owns:
- An `NSStatusItem` for the menu bar icon (dynamically rendered with work percentage and status dot)
- An `NSPopover` for the main menubar view
- Floating `NSPanel` instances for onboarding, settings, details, and objectives

The root TCA feature is `MenubarFeature`. It composes child features using `@Presents` for optional presentation and `.ifLet()` scoping:

```
MenubarFeature (root)
├── OnboardingFeature (@Presents)
│   ├── PermissionsFeature (step 1)
│   ├── ModelDownloadFeature (step 2)
│   ├── ActivityTypesFeature (step 3)
│   └── OtherSettingsFeature (step 4)
├── SettingsFeature (@Presents, 6-tab NavigationSplitView)
│   ├── Permissions tab
│   ├── Models tab
│   ├── Work Hours tab
│   ├── Activity Types tab (embeds ActivityTypesFeature)
│   ├── Debug tab
│   └── About tab
├── DetailsFeature (@Presents, floating panel)
└── ObjectivesFeature (@Presents, floating panel)
```

The menubar runs a 60-second refresh timer to keep stats current.

### 2. Recurring Tracker (LaunchAgent)

A LaunchAgent (`co.invariante.zeit`) that runs `zeit track` every 60 seconds. This is the core data collection pipeline.

The plist tick stays at 60 seconds whatever the config says: `tracking.interval_seconds` (minimum 60, default 60) is honoured by the tracking run itself, which compares the newest stored entry against the configured cadence. Changing the cadence therefore needs no service reinstall, and the plist cannot disagree with the config.

**Entry point:** `Sources/ZeitApp/CLI/TrackCommand.swift`
**Pipeline:** `Sources/ZeitApp/LLM/ActivityIdentifier.swift`

Each tracking iteration follows this pipeline:

```
Schedule → Stop flag → Battery → Cadence → Idle detection
    ↓ (if active)
 ScreenCapture.captureAllMonitors()     → [screenNumber: fileURL]
ActiveWindow.getActiveScreenNumber()   → which screen has focus
ActiveWindow.getFrontmostAppName()     → app name hint
    ↓
Vision model (e.g. qwen3-vl:4b)       → text description of screenshots
    ↓
Fetch activity types from DB           → dynamic prompt construction
Text model (e.g. qwen3:8b)            → structured JSON classification
    ↓
Parse → ActivityEntry → Save to SQLite
```

`TrackingTick.decide` is the single gate: it holds a tick off when the moment is outside the schedule, when the stop flag exists, when the machine is on battery and `tracking.skip_on_battery` is on, or when the configured cadence has not elapsed since the newest entry. The reason goes to the tracker log, and `zeit doctor` reports the same decision without acting on it. An idle system (IOKit HIDIdleTime > threshold) still records an idle entry.

### 3. CLI

An ArgumentParser-based command-line interface sharing the same binary as the GUI. Provides commands for viewing activities, managing the database, controlling services, running diagnostics, and configuring settings.

**Entry point:** `Sources/ZeitApp/CLI/ZeitCLI.swift`
**Commands:** `Sources/ZeitApp/CLI/`

The CLI accesses the database directly through `DatabaseHelper` (a lightweight wrapper around GRDB) rather than going through TCA dependency clients.

### 4. Shared Data Layer

All components read and write to the same SQLite database and YAML configuration.

**Database:** `Sources/ZeitApp/Clients/DatabaseClient.swift` (GUI), `Sources/ZeitApp/CLI/DatabaseHelper.swift` (CLI)
**Config:** `Sources/ZeitApp/Core/ZeitConfig.swift`

```
~/.local/share/zeit/
├── zeit.db          SQLite database (GRDB)
├── conf.yml         YAML configuration (Yams)
└── .zeit_stop       Flag file (presence = tracking paused)
```

Activities are stored one row per day, keyed `YYYY-MM-DD`. `DayAttribution` (`Sources/ZeitApp/Core/DayAttribution.swift`) is the only place that key is computed: an entry belongs to the day that started at `tracking.day_start_hour` local time, so `4` keeps a session that runs past midnight on the day it began. The default `0` is the calendar day. The write path attributes an entry by its own timestamp and every read — the menubar, `zeit view today`, `zeit stats` — resolves "today" the same way, so storage and views cannot disagree about where a late entry landed.

A day's entries live as a JSON array inside the row, so an optional field on `ActivityEntry` needs no migration: an absent key decodes as `nil`. `device` is such a field — the machine that produced the entry, from `device.name` or this machine's name, stamped at capture. It exists so two machines' data stays separable if it is ever exported and merged; nothing reads it across machines, and there is no device table and no sync.

## How Components Connect

```
┌──────────────┐     writes plist     ┌──────────────────┐
│  Menubar App │────────────────────→ │  LaunchAgents     │
│  (SwiftUI)   │                      │  ~/Library/       │
│              │  installs services    │  LaunchAgents/    │
└──────┬───────┘                      └────────┬──────────┘
       │                                       │
       │ reads/writes                          │ triggers every 60s
       │                                       │
       ▼                                       ▼
┌──────────────┐                      ┌──────────────────┐
│  SQLite DB   │ ◄──────────────────  │  Tracker Process  │
│  + Config    │      writes          │  (zeit track)     │
│              │                      └──────────────────┘
└──────┬───────┘
       │
       │ reads/writes
       │
       ▼
┌──────────────┐
│  CLI         │
│  (zeit ...)  │
└──────────────┘
```

- The **Menubar App** installs LaunchAgent plists and controls tracking via the `.zeit_stop` flag file. It reads the database to display stats and objectives.
- The **Tracker** (launched by launchd) runs the capture-and-classify pipeline and writes results to the database. It reads the config for work hours and model settings.
- The **CLI** reads the database for viewing/stats and writes to it for data management. It also manages LaunchAgent installation and config updates.
- All three share the **SQLite database** and **YAML config** as their integration point. No IPC or networking between components.

## Key Patterns

### TCA Reducer Composition

Every UI feature is a TCA `@Reducer` with `@ObservableState`. Parent features compose children using:

```swift
@Presents var child: ChildFeature.State?

// In the reducer body:
Reduce { state, action in ... }
.ifLet(\.$child, action: \.child) { ChildFeature() }
```

### Dependency Injection

External services are abstracted behind `@DependencyClient` interfaces:

| Client | Responsibility |
|--------|---------------|
| `DatabaseClient` | Read/write activities, objectives, activity types |
| `TrackingClient` | Tracking state, work hours check, start/stop |
| `ModelClient` | Model download status and downloads |
| `PermissionsClient` | Read the Screen Recording and Accessibility grants, and guide the user through giving them |
| `LaunchAgentClient` | Service install, load, unload, restart |
| `NotificationClient` | macOS notification delivery |
| `ClassificationClient` | Read/write `classification.primary_group` in `conf.yml` |

### Actor-Based Database Access

The GUI's `DatabaseClient` uses an actor (`DatabaseActor`) for thread-safe GRDB access. The CLI's `DatabaseHelper` uses simpler synchronous access since CLI commands are short-lived.

Both open the same file and both bring it up to date through `ZeitDatabase` (`Sources/ZeitApp/Clients/DatabaseSchema.swift`), a GRDB `DatabaseMigrator` whose first migration is a baseline matching the original `CREATE TABLE IF NOT EXISTS` schema. Schema changes go there, so the two paths cannot disagree.

### Two-Stage LLM Pipeline

Activity identification always uses two models:
1. **Vision model** — processes screenshots into a text description using `MLXClient.generateWithVisionThinking()`
2. **Text model** — classifies the description into an activity category using `MLXClient.generateStructured()` with a dynamically constructed JSON schema

The pipeline directly uses `MLXClient` for on-device inference. An `LLMProvider` protocol exists as a potential foundation for future abstraction but is not currently used in the active pipeline.

### Single Binary, Dual Mode

`main.swift` inspects `CommandLine.arguments` to decide between GUI and CLI mode. No arguments (or Finder's `-psn` flag) starts the SwiftUI app; any arguments route to the ArgumentParser CLI. One build target, one executable.

### Async/Await Throughout

All side effects use Swift concurrency. TCA effects use `.run { send in ... }` blocks. Timers use `clock.timer(interval:)` with cancellation IDs. Permission observation uses `AsyncStream`.
