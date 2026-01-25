# CLAUDE.md

**Updated:** 2026-01-24 | **Branch:** main

## Overview

macOS activity tracker: periodic screenshots → Ollama vision model → activity classification → SQLite storage. Unified CLI + menubar app + launchd scheduling.

## Tech Stack

- Python 3.11+ / uv
- PySide6 (Qt menubar)
- Typer (CLI framework)
- Ollama: `qwen3-vl:4b` (vision), `qwen3:8b` (classification)
- py2app (macOS .app bundle)
- PyInstaller (standalone CLI binary)
- Opik (LLM observability, optional)
- Ruff (linting + formatting)
- mypy (type checking)
- pre-commit (git hooks)

## Structure

```
src/zeit/
├── cli/                    # CLI tools
│   ├── main.py             # Unified `zeit` CLI entry point
│   ├── view_data.py        # View activity history commands
│   ├── db.py               # Database management commands
│   └── service.py          # LaunchAgent service management
├── core/                   # Core functionality
│   ├── active_window.py    # macOS API: focused window detection
│   ├── activity_id.py      # ActivityIdentifier class (LLM logic)
│   ├── activity_types.py   # Activity, ExtendedActivity enums
│   ├── config.py           # YAML config loader
│   ├── idle_detection.py   # IOKit idle time check
│   ├── logging_config.py   # Centralized logging setup
│   ├── macos_helpers.py    # AppleScript execution helpers
│   ├── models.py           # Pydantic response models
│   ├── prompts.py          # LLM prompt templates
│   ├── screen.py           # Multi-screen capture (mss)
│   └── utils.py            # Date utilities
├── data/                   # Persistence
│   └── db.py               # SQLite: daily_activities, day_objectives tables
├── processing/             # Data processing
│   ├── activity_summarization.py  # Activity condensation/grouping
│   └── day_summarizer.py          # LLM-based day summaries
└── ui/                     # UI components
    ├── menubar.py          # Main menubar app
    ├── objectives_dialog.py # Set day objectives dialog
    ├── details_window.py   # Detailed activity view
    ├── tracking_state.py   # Tracking state management
    └── qt_helpers.py       # Qt utilities
```

## Unified CLI

The `zeit` command provides all functionality:

```bash
# View activities
zeit view today              # Today's activities
zeit view yesterday          # Yesterday's activities
zeit view all                # All days summary
zeit view day 2025-01-07     # Specific day
zeit summarize [date]        # AI-generated day summary

# Day objectives
zeit view objectives [date]               # View objectives
zeit view set-objectives --main "..." [--opt1 "..."]  # Set objectives
zeit view delete-objectives <date>        # Delete objectives

# Database management
zeit db info                 # Database stats
zeit db delete-today         # Delete today's data
zeit db delete-day <date>    # Delete specific day
zeit db delete-objectives <date>  # Delete objectives

# Service management
zeit service status          # Check LaunchAgent status
zeit service start           # Resume tracking (remove stop flag)
zeit service stop            # Pause tracking (create stop flag)
zeit service install --cli <path> --app <path>  # Install services
zeit service uninstall       # Remove LaunchAgents
zeit service restart         # Restart tracker

# Tracking
zeit track [--delay N]       # Single capture (called by launchd)
zeit version                 # Show version
```

## Entry Points

| Method | Purpose | Command |
|--------|---------|---------|
| Unified CLI | All commands | `uv run zeit <command>` |
| Menubar app | UI | `uv run python run_menubar_app.py` |
| Dev tracker | Single capture | `uv run python run_tracker.py` |
| Built binary | Standalone | `./dist/zeit <command>` |

## Database Schema

```sql
-- data/zeit.db

CREATE TABLE daily_activities (
    date TEXT PRIMARY KEY,      -- YYYY-MM-DD
    activities TEXT NOT NULL,   -- JSON array of ActivityEntry
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE day_objectives (
    date TEXT PRIMARY KEY,            -- YYYY-MM-DD
    main_objective TEXT NOT NULL,     -- Primary goal for the day
    secondary_objectives TEXT,        -- JSON array of strings
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
```

## Build & Installation

```bash
# Build everything (checks + app + CLI)
./build_all.sh

# Build options
./build_all.sh --skip-cli       # Skip CLI binary
./build_all.sh --skip-app       # Skip menubar app
./build_all.sh --skip-checks    # Skip linting/type checks
./build_all.sh --install        # Install after build

# Install from built artifacts
python scripts/install.py install --cli dist/zeit --app dist/Zeit.app
python scripts/install.py uninstall
python scripts/install.py status
```

## Where to Look

| Task | Location |
|------|----------|
| Add CLI command | `src/zeit/cli/` (main.py, view_data.py, db.py, service.py) |
| Add activity category | `src/zeit/core/activity_types.py` → Activity, ExtendedActivity |
| Modify LLM prompts | `src/zeit/core/prompts.py` |
| Modify LLM response models | `src/zeit/core/models.py` |
| Change screenshot behavior | `src/zeit/core/screen.py` → MultiScreenCapture |
| Modify idle detection | `src/zeit/core/idle_detection.py` |
| Add menubar features | `src/zeit/ui/menubar.py` |
| Add dialog | `src/zeit/ui/` (see objectives_dialog.py) |
| Change database schema | `src/zeit/data/db.py` → _create_tables() |
| Modify work hours | `~/.local/share/zeit/conf.yml` (or edit bundled default) |
| Change data paths | `src/zeit/core/config.py` → DATA_DIR, PathsConfig |
| Modify build process | `build_all.sh`, `zeit_cli.spec` |
| Installation logic | `scripts/install.py`, `src/zeit/cli/service.py` |

## Activity Categories

**Personal**: personal_browsing, social_media, youtube_entertainment, personal_email, personal_ai_use, personal_finances, professional_development, online_shopping, personal_calendar, entertainment

**Work**: slack, work_email, zoom_meeting, work_coding, work_browsing, work_calendar

**System**: idle (auto-detected via IOKit)

## Data Directory

All runtime data is stored in `~/.local/share/zeit/`:

| File | Purpose |
|------|---------|
| `conf.yml` | User config (copied from bundled default on first run) |
| `zeit.db` | SQLite database with activities and objectives |
| `.zeit_stop` | Flag file to pause tracking |

## Configuration

| File | Purpose |
|------|---------|
| `~/.local/share/zeit/conf.yml` | User config: work hours, model names, paths |
| `src/zeit/core/conf.yml` | Bundled default config (copied to user dir on first run) |
| `.env` | Runtime env vars |
| `pyproject.toml` | Dependencies, CLI entry point, tool configs |
| `zeit_cli.spec` | PyInstaller build config |
| `entitlements.plist` | macOS code signing permissions |

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `IDLE_THRESHOLD_SECONDS` | 300 | Seconds before marking as idle |
| `OPIK_URL` | — | Local Opik instance URL (optional) |

## Commands

```bash
# Development
uv sync                           # Install deps
uv run zeit --help                # CLI help
uv run zeit view today            # View today
uv run python run_menubar_app.py  # Menubar app

# Linting & Formatting
uv run ruff check .               # Lint
uv run ruff check --fix .         # Lint + auto-fix
uv run ruff format .              # Format
uv run mypy src/                  # Type check
uv run pre-commit run --all-files # Run all hooks

# Build
./build_all.sh                    # Full build with checks
uv run pyinstaller zeit_cli.spec  # Build CLI binary only
```

## Code Conventions

- Type hints everywhere (enforced by ruff ANN rules)
- Modern Python syntax: `list[X]` not `List[X]`, `X | None` not `Optional[X]`
- Pydantic models for structured data
- Context managers for resources (DatabaseManager, MultiScreenCapture)
- Logging: file (DEBUG) + console (INFO)
- Line length: 100 characters
- Pre-commit hooks run automatically on `git commit`

## Design Decisions

### Opik is Optional

Opik (LLM observability) has heavy dependencies (litellm) that complicate packaging. The import is wrapped in try/except and becomes a no-op when unavailable.

### Activity vs ExtendedActivity Enums

- **Activity**: Used in LLM prompts. Does NOT include IDLE (detected via IOKit).
- **ExtendedActivity**: Used for storage. Includes Activity values + IDLE.

### Unified CLI Architecture

All commands go through `zeit` binary:
- `zeit view` → view_data.py
- `zeit db` → db.py
- `zeit service` → service.py
- `zeit track` → main.py (inline)

## Notes

- **Multi-monitor**: Captures all screens, detects active screen via native API
- **Ollama required**: Must have models pulled (`ollama pull qwen3-vl:4b qwen3:8b`)
- **Permissions**: Requires Screen Recording permission
- **LaunchAgents**: Installed to ~/Library/LaunchAgents/
- **Logs**: Written to ~/Library/Logs/zeit/
