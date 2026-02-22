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

A LaunchAgent (`co.invariante.zeit`) that runs `zeit track` every 60 seconds during configured work hours. This is the core data collection pipeline.

**Entry point:** `Sources/ZeitApp/CLI/TrackCommand.swift`
**Pipeline:** `Sources/ZeitApp/LLM/ActivityIdentifier.swift`

Each tracking iteration follows this pipeline:

```
Work hours check → Stop flag check → Idle detection
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

The tracker skips silently when outside work hours, when the stop flag exists, or when the system is idle (IOKit HIDIdleTime > threshold).

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
| `PermissionsClient` | Screen Recording and Accessibility permission checks |
| `LaunchAgentClient` | Service install, load, unload, restart |
| `NotificationClient` | macOS notification delivery |

### Actor-Based Database Access

The GUI's `DatabaseClient` uses an actor (`DatabaseActor`) for thread-safe GRDB access. The CLI's `DatabaseHelper` uses simpler synchronous access since CLI commands are short-lived.

### Two-Stage LLM Pipeline

Activity identification always uses two models:
1. **Vision model** — processes screenshots into a text description
2. **Text model** — classifies the description into an activity category using structured JSON output with a schema

Both stages are abstracted behind `LLMProvider` / `VisionLLMProvider` protocols, with `MLXClient` (on-device) and `OpenAIClient` (remote) as implementations.

### Single Binary, Dual Mode

`main.swift` inspects `CommandLine.arguments` to decide between GUI and CLI mode. No arguments (or Finder's `-psn` flag) starts the SwiftUI app; any arguments route to the ArgumentParser CLI. One build target, one executable.

### Async/Await Throughout

All side effects use Swift concurrency. TCA effects use `.run { send in ... }` blocks. Timers use `clock.timer(interval:)` with cancellation IDs. Permission observation uses `AsyncStream`.
