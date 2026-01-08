# AGENTS.md

**Generated:** 2026-01-07 | **Commit:** 9d5c221 | **Branch:** main

## Overview

macOS activity tracker: periodic screenshots → Ollama vision model → activity classification → SQLite storage. Menubar app + launchd scheduling.

## Tech Stack

- Python 3.11+ / uv
- PySide6 (Qt menubar)
- Ollama: `qwen3-vl:4b` (vision), `qwen3:8b` (classification)
- py2app (macOS .app bundle)
- Opik (LLM observability, optional)

## Structure

```
src/zeit/
├── cli/           # CLI tools
│   └── view_data.py       # View activity history
├── core/          # Core functionality
│   ├── active_window.py   # macOS API: focused window detection
│   ├── activity_id.py     # Activity enum + ActivityIdentifier (LLM logic)
│   ├── config.py          # YAML config loader
│   ├── idle_detection.py  # IOKit idle time check
│   └── screen.py          # Multi-screen capture (mss)
├── data/          # Persistence
│   └── db.py              # SQLite: daily_activities table
├── processing/    # Data processing
│   ├── activity_summarization.py
│   └── day_summarizer.py
└── ui/            # UI components
    ├── menubar.py         # Main menubar app (511 lines)
    └── qt_helpers.py      # Qt utilities
```

## Entry Points

| File | Purpose | Run With |
|------|---------|----------|
| `run_tracker.py` | Main tracker (single capture) | `uv run python run_tracker.py [delay_seconds]` |
| `run_menubar_app.py` | Menubar UI | `uv run python run_menubar_app.py` |
| `run_view_data.py` | View data CLI | `uv run python run_view_data.py` |
| `manage_db.py` | DB management | `uv run python manage_db.py` |

## Where to Look

| Task | Location |
|------|----------|
| Add new activity category | `src/zeit/core/activity_id.py` → `Activity` and `ExtendedActivity` enums |
| Modify LLM prompts | `src/zeit/core/activity_id.py` → `MULTI_SCREEN_DESCRIPTION_PROMPT_BASE`, `_describe_activities()` |
| Change screenshot behavior | `src/zeit/core/screen.py` → `MultiScreenCapture` |
| Modify idle detection | `src/zeit/core/idle_detection.py` |
| Add menubar features | `src/zeit/ui/menubar.py` |
| Change database schema | `src/zeit/data/db.py` → `_create_tables()` |
| Modify work hours | `src/zeit/core/conf.yml` |

## Activity Categories

**Personal**: personal_browsing, social_media, youtube_entertainment, personal_email, personal_ai_use, personal_finances, professional_development, online_shopping, personal_calendar, entertainment

**Work**: slack, work_email, zoom_meeting, work_coding, work_browsing, work_calendar

**System**: idle (auto-detected via IOKit)

## Database Schema

```sql
-- data/zeit.db
CREATE TABLE daily_activities (
    date TEXT PRIMARY KEY,      -- YYYY-MM-DD
    activities TEXT NOT NULL,   -- JSON array of ActivityEntry
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
```

## Configuration

| File | Purpose |
|------|---------|
| `src/zeit/core/conf.yml` | Work hours (work_start_hour, work_end_hour) |
| `.env` | Runtime env vars (copy from `.env.example`) |
| `co.invariante.zeit.plist` | launchd scheduler (StartInterval: 60s default) |
| `entitlements.plist` | macOS permissions for code signing |

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `IDLE_THRESHOLD_SECONDS` | 300 | Seconds before marking as idle |
| `OPIK_URL` | — | Local Opik instance URL for LLM tracing |

## Commands

```bash
# Development
uv sync                           # Install deps
uv run python run_tracker.py      # Single capture
uv run python run_menubar_app.py  # Menubar app

# Build
sh ./build_app.sh            # Build .app bundle and sign
```

## Code Conventions

- Type hints everywhere
- Pydantic models for structured data (ActivityEntry, DayRecord, ActivitiesResponse)
- Context managers for resources (DatabaseManager, MultiScreenCapture)
- Logging: file (DEBUG) + console (INFO) via `setup_logging()`

## Notes

- **Multi-monitor**: Captures all screens, uses native macOS API to detect active screen, vision model verifies
- **Ollama required**: Must have `qwen3-vl:4b` and `qwen3:8b` models pulled
- **Permissions**: Requires Screen Recording permission for screenshots
- **No tests**: Test suite not yet implemented
