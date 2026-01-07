# AGENTS.md

## Project Overview

**Zeit** is a macOS activity tracker that logs user activity via periodic screenshots and summarizes it using local LLMs (Ollama). It runs as a menubar app and uses launchd for scheduling.

## Tech Stack

- **Language**: Python 3.11+
- **Package Manager**: uv
- **UI Framework**: PySide6 (Qt)
- **LLM Backend**: Ollama (qwen3-vl for vision, qwen2 for text)
- **Build**: py2app for macOS .app bundle

## Project Structure

```
src/zeit/
├── cli/           # CLI tools (view_data.py)
├── core/          # Core functionality
│   ├── active_window.py   # Get active window info
│   ├── activity_id.py     # Activity enum definitions
│   ├── config.py          # Configuration loading
│   ├── idle_detection.py  # User idle detection
│   └── screen.py          # Screenshot capture
├── processing/    # Data processing
│   └── activity_summarization.py  # LLM-based summarization
└── ui/            # UI components
    ├── menubar.py     # Menubar app
    └── qt_helpers.py  # Qt utilities
```

## Key Entry Points

| File | Purpose |
|------|---------|
| `run_tracker.py` | Main tracker daemon |
| `run_menubar_app.py` | Menubar UI app |
| `run_view_data.py` | View collected data |
| `manage_db.py` | Database management |

## Configuration

- `src/zeit/core/conf.yml` - Main config file
- `.env` - Environment variables (copy from `.env.example`)
- `co.invariante.zeit.plist` - launchd scheduler config

## Development Commands

```bash
# Install dependencies
uv sync

# Run tracker
uv run python run_tracker.py

# Run menubar app
uv run python run_menubar_app.py

# Build macOS app
python setup.py py2app
```

## Code Conventions

- Use type hints as frequently as possible
- Follow existing patterns in the codebase
- Keep modules focused and small
