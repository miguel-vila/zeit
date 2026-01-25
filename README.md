# zeit

Logs what you are doing in your computer and summarizes it using local models:

- `qwen3-vl` for image captioning
- `qwen2` to infer the activity based on the captions

## Configs

- **Work hours and days**: Edit `run_tracker.sh` to set `WORK_START_HOUR` and `WORK_END_HOUR`
- **Idle threshold**: Set `IDLE_THRESHOLD_SECONDS` environment variable in `.env` file (default: 300 seconds / 5 minutes)
- **Activities enumeration**: Defined in `activity_id.py` as `Activity` enum

## TODOs

- ~~build this as an executable (py2app?)~~ (see Build section below)
- handle permissions better (maybe building this as an app helps?)
- add last half an hour summary in the menubar app
- collect only necessary data
- day summary report at the end of the day
- select which monitor to capture from according to user focus? or just take it from all monitors?
- user gives a general description of what their main objective is during the day, with specifics (e.g., working on project X, writing report Y)
  and the model uses that to better classify activities and to generate an objective-aligned summary at the end of the day
- use playing audio as a signal of activity (e.g., when watching videos and multitasking)
- idle should not be counted
- preconfigure ollama models to download
- do main screen identification using macos APIs ()
- test single screen

## Building as a macOS App

You can build Zeit as a standalone macOS `.app` bundle using py2app:

```bash
# Build the app (creates dist/Zeit.app)
python setup.py py2app

# For development/testing (faster, uses symlinks)
python setup.py py2app -A
```

### Code Signing

For proper permission handling, sign the app after building:

```bash
# Self-sign for local use
codesign --force --deep --sign - dist/Zeit.app

# Or with Apple Developer ID for distribution
codesign --force --deep --sign "Developer ID Application: Your Name" \
    --entitlements entitlements.plist dist/Zeit.app
```

### Running the App

```bash
# Run directly
open dist/Zeit.app

# Or from terminal to see logs
./dist/Zeit.app/Contents/MacOS/Zeit
```

### Clean Build

```bash
rm -rf build dist .eggs
```
