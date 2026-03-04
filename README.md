# zeit

macOS activity tracker: periodic screenshots → LLM vision model → activity classification → SQLite storage. Single Swift executable runs as both menubar app and CLI.

## Features

- **Activity tracking**: Screenshots → vision model → activity classification every 60 seconds
- **Multiple LLM providers**: MLX (on-device, default), OpenAI
- **Menubar app**: Live tracking state, activity stats, objectives
- **CLI**: View history, statistics, day summaries, service management
- **LaunchAgent scheduling**: Automatic tracking during work hours

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon (for MLX on-device inference) or OpenAI as alternative

## Building

```bash
# Debug build
./build.sh

# Release build and install to /Applications
./build.sh --release --install

# Signed release with DMG
./build.sh --release --sign --dmg
```

See [docs/BUILD.md](docs/BUILD.md) for signing and notarization details.

## Usage

```bash
# GUI mode (menubar app)
open dist/Zeit.app

# CLI
./dist/Zeit.app/Contents/MacOS/Zeit view today
./dist/Zeit.app/Contents/MacOS/Zeit stats
./dist/Zeit.app/Contents/MacOS/Zeit track --force
./dist/Zeit.app/Contents/MacOS/Zeit --help
```

## Configuration

Edit `~/.local/share/zeit/conf.yml`:

```yaml
work_hours:
  start_hour: 9
  start_minute: 0
  end_hour: 17
  end_minute: 30

models:
  vision: 'qwen3-vl:4b'
  text:
    provider: 'mlx'     # 'mlx' (on-device) or 'openai'
    model: 'qwen3:8b'
```

## Permissions

- **Screen Recording** — for screenshot capture
- **Automation/AppleScript** — for active window detection
