# CLI Reference

The CLI shares the same binary as the menubar app. When the `ZeitApp` executable receives command-line arguments, it routes to the ArgumentParser CLI instead of launching the SwiftUI app.

```bash
# These are equivalent:
./dist/Zeit.app/Contents/MacOS/ZeitApp view today
zeit view today   # if aliased or symlinked
```

## Commands

### `zeit version`

Show version information.

```
zeit version 0.2.0 (Swift)
```

### `zeit track`

Run a single tracking iteration (screenshot capture, LLM classification, database save).

```bash
zeit track [--delay N] [--force] [--debug]
```

| Flag | Description |
|------|-------------|
| `--delay N` | Wait N seconds before capturing (default: 0) |
| `--force` | Ignore work hours and stop flag |
| `--debug` | Keep screenshots in `/tmp` and print their paths |

This is the command that the LaunchAgent runs every 60 seconds. See [Recurring Tracking](recurring-tracking.md) for the full pipeline.

### `zeit doctor`

Run system diagnostics.

```bash
zeit doctor [--json]
```

Checks:
- Vision and text models downloaded
- Screen Recording and Accessibility permissions granted
- Data directory, database, and log directory exist
- Tracker and menubar LaunchAgent plists installed
- Tracker and menubar services running

Exit code: 0 if all checks pass, 1 if any fail.

With `--json`, outputs machine-readable JSON instead of the formatted table.

---

## View Commands

### `zeit view today` / `zeit view yesterday`

Show activities for today or yesterday.

Output: timestamped list of activities with icons (work/personal/idle), followed by a summary with work/personal/idle percentages.

### `zeit view day <YYYY-MM-DD>`

Show activities for a specific date.

### `zeit view all`

List all tracked days with activity counts.

### `zeit view summarize`

Generate an AI-powered summary of a day's activities.

```bash
zeit view summarize [YYYY-MM-DD] [-m PROVIDER:MODEL]
```

| Option | Description |
|--------|-------------|
| `YYYY-MM-DD` | Date to summarize (default: today) |
| `-m, --model` | Override model in `provider:model` format (e.g. `openai:gpt-4o-mini`) |

The summary includes time distribution, activity patterns, and a productivity assessment. If day objectives are set, they are referenced in the summary.

### `zeit view objectives`

View objectives for a day.

```bash
zeit view objectives [YYYY-MM-DD]
```

### `zeit view set-objectives`

Set day objectives.

```bash
zeit view set-objectives --main "..." [--opt1 "..."] [--opt2 "..."] [YYYY-MM-DD]
```

| Option | Description |
|--------|-------------|
| `--main` | Main objective (required) |
| `--opt1` | First secondary objective |
| `--opt2` | Second secondary objective |
| `YYYY-MM-DD` | Date (default: today) |

### `zeit view delete-objectives`

Delete objectives for a day.

```bash
zeit view delete-objectives <YYYY-MM-DD> [--force]
```

`--force` skips the confirmation prompt.

---

## Stats Commands

### `zeit stats`

Show activity statistics for a day.

```bash
zeit stats [YYYY-MM-DD] [--json] [--include-idle]
```

| Flag | Description |
|------|-------------|
| `YYYY-MM-DD` | Date (default: today) |
| `--json` | Output as JSON |
| `--include-idle` | Include idle time in statistics (excluded by default) |

Output includes total sample count, work/personal/idle percentages, and a per-activity breakdown with bar chart visualization.

---

## Database Commands

### `zeit db info`

Show database path, file size, modification date, days tracked, and total activity count.

### `zeit db delete-today`

Delete all activities for today.

```bash
zeit db delete-today [--force]
```

### `zeit db delete-day`

Delete all activities for a specific day.

```bash
zeit db delete-day <YYYY-MM-DD> [--force]
```

### `zeit db delete-objectives`

Delete objectives for a specific day.

```bash
zeit db delete-objectives <YYYY-MM-DD> [--force]
```

All delete commands prompt for confirmation unless `--force` is used.

---

## Service Commands

Manage the LaunchAgent services that power background tracking and the menubar app.

### `zeit service status`

Show installation and running status of both services (tracker and menubar), plus tracking active state and work hours.

### `zeit service start`

Resume tracking by removing the `.zeit_stop` flag file.

### `zeit service stop`

Pause tracking by creating the `.zeit_stop` flag file. The LaunchAgent still fires every 60 seconds, but `zeit track` exits immediately when it sees the flag.

### `zeit service install`

Install LaunchAgent plists to `~/Library/LaunchAgents/`.

```bash
zeit service install [--cli PATH] [--app PATH]
```

| Option | Description |
|--------|-------------|
| `--cli PATH` | Path to CLI binary (auto-detected if omitted) |
| `--app PATH` | Path to menubar app (auto-detected if omitted) |

Installs two LaunchAgents:
- `co.invariante.zeit` - runs `zeit track` every 60 seconds
- `co.invariante.zeit.menubar` - launches the menubar app at login

### `zeit service uninstall`

Unload and remove both LaunchAgent plists.

### `zeit service restart`

Restart the tracker service immediately using `launchctl kickstart`.

---

## Configuration Commands

### `zeit set-work-hours`

```bash
zeit set-work-hours --start HH:MM --end HH:MM [--days DAYS]
```

| Option | Description |
|--------|-------------|
| `--start` | Start time (e.g. `9:00`, `09:00`) |
| `--end` | End time (e.g. `17:30`) |
| `--days` | Comma-separated work days (e.g. `mon,tue,wed,thu,fri`) |

### `zeit list-activity-types`

List all configured activity types grouped by work/personal.

### `zeit set-activity-types`

```bash
zeit set-activity-types [--work TYPES] [--personal TYPES]
```

Types are semicolon-separated `Name: Description` pairs:

```bash
zeit set-activity-types --work "Coding: Writing code; Design: UI work"
```

If only `--work` is provided, existing personal types are preserved (and vice versa).

---

## Data Locations

| Path | Purpose |
|------|---------|
| `~/.local/share/zeit/zeit.db` | SQLite database |
| `~/.local/share/zeit/conf.yml` | YAML configuration |
| `~/.local/share/zeit/.zeit_stop` | Tracking pause flag |
| `~/Library/LaunchAgents/co.invariante.zeit.plist` | Tracker LaunchAgent |
| `~/Library/LaunchAgents/co.invariante.zeit.menubar.plist` | Menubar LaunchAgent |
| `~/Library/Logs/zeit/` | Log files |
