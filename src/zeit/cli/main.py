#!/usr/bin/env python3
"""
Zeit CLI - Unified command-line interface for Zeit activity tracker.

Commands:
    zeit view today          View today's activities
    zeit view yesterday      View yesterday's activities
    zeit view all            View all days
    zeit view day <date>     View specific day
    zeit view summarize      Generate AI summary

    zeit stats [date]        Show activity statistics (excludes idle by default)

    zeit db info             Database information
    zeit db delete-today     Delete today's data

    zeit service install     Install LaunchAgents
    zeit service uninstall   Remove LaunchAgents
    zeit service status      Check service status
    zeit service start       Start tracker
    zeit service stop        Stop tracker

    zeit track               Run single tracking iteration (for launchd)
"""

import logging
import os
from datetime import datetime
from time import sleep

import typer

from zeit import __version__
from zeit.cli.db import app as db_app
from zeit.cli.service import app as service_app
from zeit.cli.view_data import app as view_app

app = typer.Typer(
    name="zeit",
    help="Zeit activity tracker CLI",
    add_completion=True,
    no_args_is_help=True,
)

# Register sub-commands
app.add_typer(view_app, name="view", help="View activity data")
app.add_typer(db_app, name="db", help="Database management")
app.add_typer(service_app, name="service", help="Service management")


@app.command()
def track(
    delay: int = typer.Option(0, "--delay", "-d", help="Delay in seconds before tracking"),
    force: bool = typer.Option(
        False, "--force", "-f", help="Bypass work hours and stop flag checks"
    ),
) -> None:
    """
    Run single tracking iteration.

    This command is called by launchd every 60 seconds.
    It checks work hours, idle state, and captures activity.
    """
    # Imports here to avoid circular imports and speed up CLI startup
    from dotenv import load_dotenv
    from ollama import Client

    from zeit.core.activity_id import ActivityIdentifier
    from zeit.core.config import get_config, is_within_work_hours
    from zeit.core.idle_detection import DEFAULT_IDLE_THRESHOLD, is_system_idle
    from zeit.core.logging_config import setup_logging
    from zeit.data.db import ActivityEntry, DatabaseManager

    load_dotenv()
    setup_logging(log_file="zeit.log")
    logger = logging.getLogger(__name__)

    # Opik is optional - only configure if available and URL is set
    if os.getenv("OPIK_URL"):
        try:
            import opik

            logger.info(f"Running with local Opik instance at {os.getenv('OPIK_URL')}")
            opik.configure(url=os.getenv("OPIK_URL"), use_local=True)
        except ImportError:
            logger.debug("Opik not available, skipping tracing configuration")

    logger.info("=" * 60)
    logger.info("Starting zeit activity tracker")

    # Check work hours
    if not force and not is_within_work_hours():
        logger.debug("Outside work hours, skipping")
        raise typer.Exit(0)

    # Check stop flag
    config = get_config()
    stop_flag = config.paths.stop_flag
    if not force and stop_flag.exists():
        logger.debug("Stop flag set, skipping")
        raise typer.Exit(0)

    if force:
        logger.info("Force mode enabled, bypassing work hours and stop flag checks")

    # Optional delay
    if delay > 0:
        logger.info(f"Waiting for {delay} seconds before taking screenshot...")
        sleep(delay)

    # Check idle
    idle_threshold = int(os.getenv("IDLE_THRESHOLD_SECONDS", str(DEFAULT_IDLE_THRESHOLD)))
    logger.debug(f"Using idle threshold: {idle_threshold} seconds")

    if is_system_idle(idle_threshold):
        logger.info("System is idle, recording idle state instead of taking screenshot")
        idle_entry = ActivityEntry.idle(datetime.now())
        with DatabaseManager() as db:
            success = db.insert_activity(idle_entry)
            if not success:
                logger.error("Failed to save idle state to database")
                raise typer.Exit(1)
            logger.info("Idle state successfully saved to database")
        raise typer.Exit(0)

    # System is active - proceed with screenshot and identification
    logger.debug("Initializing Ollama client")
    client = Client()
    config = get_config()
    identifier = ActivityIdentifier(ollama_client=client, models_config=config.models)

    # Take screenshot and identify activity
    activities_response = identifier.take_screenshot_and_describe()

    if activities_response is None:
        logger.error("Failed to identify activity")
        raise typer.Exit(1)

    # Log results
    logger.info("=" * 60)
    logger.info(f"Activity: {activities_response.main_activity.value}")
    logger.info(f"Reasoning: {activities_response.reasoning}")
    logger.info("=" * 60)

    # Save to database
    logger.debug("Saving activity to database")
    with DatabaseManager() as db:
        activity_entry = ActivityEntry.from_response(activities_response)
        success = db.insert_activity(activity_entry)

        if not success:
            logger.error("Failed to save activity to database")
            raise typer.Exit(1)

        logger.info("Activity successfully saved to database")


@app.command()
def stats(
    date: str = typer.Argument(None, help="Date in YYYY-MM-DD format (defaults to today)"),
    json_output: bool = typer.Option(False, "--json", "-j", help="Output as JSON"),
    include_idle: bool = typer.Option(False, "--include-idle", help="Include idle time in stats"),
) -> None:
    """Show activity statistics for a day.

    Displays a breakdown of time spent on each activity type,
    grouped by category (work, personal). Idle time is excluded by default.

    Examples:
        zeit stats                  # Today's stats (excludes idle)
        zeit stats 2026-01-30       # Specific day
        zeit stats --include-idle   # Include idle time
        zeit stats --json           # JSON output for scripts
    """
    # Import here to avoid slowing down CLI startup
    from zeit.cli.view_data import cmd_stats

    cmd_stats(date, json_output, include_idle)


@app.command()
def version() -> None:
    """Show version information."""
    typer.echo(f"Zeit version {__version__}")


@app.command("check-update")
def check_update() -> None:
    """
    Check for available updates.

    Checks GitHub releases for newer versions of Zeit.
    """
    import json
    import urllib.request

    from rich import print as rprint

    GITHUB_REPO = "miguelvilagonzalez/zeit"
    RELEASES_URL = f"https://api.github.com/repos/{GITHUB_REPO}/releases/latest"

    rprint(f"Current version: [cyan]{__version__}[/cyan]")
    rprint("Checking for updates...")

    try:
        req = urllib.request.Request(
            RELEASES_URL,
            headers={"Accept": "application/vnd.github.v3+json", "User-Agent": "Zeit"},
        )
        with urllib.request.urlopen(req, timeout=10) as response:
            data = json.loads(response.read().decode())

        latest_version = data.get("tag_name", "").lstrip("v")
        release_url = data.get("html_url", "")

        if not latest_version:
            rprint("[yellow]Could not determine latest version[/yellow]")
            return

        # Simple version comparison (works for semver)
        current_parts = [int(x) for x in __version__.split(".")]
        latest_parts = [int(x) for x in latest_version.split(".")]

        if latest_parts > current_parts:
            rprint(f"\n[green]New version available: {latest_version}[/green]")
            rprint(f"Download: {release_url}")
        else:
            rprint("\n[green]You're running the latest version![/green]")

    except urllib.error.URLError as e:
        rprint(f"[yellow]Could not check for updates: {e.reason}[/yellow]")
    except json.JSONDecodeError:
        rprint("[yellow]Could not parse update response[/yellow]")
    except ValueError:
        rprint("[yellow]Could not compare versions[/yellow]")


@app.command()
def doctor() -> None:
    """
    Check system setup and diagnose issues.

    Verifies Ollama, models, permissions, and services are properly configured.
    """
    import shutil
    import subprocess

    from rich import print as rprint
    from rich.table import Table

    from zeit.core.config import get_config

    checks: list[tuple[str, bool, str]] = []

    # Check 1: Ollama installed
    ollama_path = shutil.which("ollama")
    checks.append(("Ollama installed", ollama_path is not None, ollama_path or "not found"))

    # Check 2: Ollama running
    ollama_running = False
    try:
        result = subprocess.run(["ollama", "list"], capture_output=True, text=True, timeout=5)
        ollama_running = result.returncode == 0
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass
    checks.append(("Ollama running", ollama_running, ""))

    # Check 3: Required models (only check Ollama models)
    config = get_config()
    required_models = [config.models.vision]
    if config.models.text.provider == "ollama":
        required_models.append(config.models.text.model)

    for model in required_models:
        model_present = False
        if ollama_running:
            try:
                result = subprocess.run(
                    ["ollama", "show", model], capture_output=True, text=True, timeout=10
                )
                model_present = result.returncode == 0
            except (subprocess.TimeoutExpired, FileNotFoundError):
                pass
        hint = f"ollama pull {model}" if not model_present else ""
        checks.append((f"Model: {model}", model_present, hint))

    # Check 4: macOS Permissions
    # Note: macOS permissions are per-executable. Only meaningful when running as installed binary.
    import sys

    is_frozen = getattr(sys, "frozen", False)  # True when running as PyInstaller bundle

    from zeit.core.permissions import get_all_permission_statuses

    if is_frozen:
        # Running as installed binary - check permissions normally
        for perm in get_all_permission_statuses():
            hint = f"Open: {perm.settings_url}" if not perm.granted else ""
            checks.append((f"Permission: {perm.name}", perm.granted, hint))
    else:
        # Running from source (uv run) - permissions check would be for Python interpreter
        # which is not useful. Skip the check and explain.
        checks.append(
            (
                "Permissions (dev mode)",
                True,
                "Skipped - run installed binary to check",
            )
        )

    # Check 5: Database directory and file
    paths = config.paths
    checks.append(("Data directory", paths.data_dir.exists(), str(paths.data_dir)))
    checks.append(("Database file", paths.db_path.exists(), str(paths.db_path)))

    # Check 6: Log directory
    from zeit.core.config import LAUNCH_AGENTS_DIR, LOG_DIR

    checks.append(("Log directory", LOG_DIR.exists(), str(LOG_DIR)))

    # Check 7: LaunchAgents
    tracker_plist = LAUNCH_AGENTS_DIR / "co.invariante.zeit.plist"
    menubar_plist = LAUNCH_AGENTS_DIR / "co.invariante.zeit.menubar.plist"

    checks.append(("Tracker LaunchAgent", tracker_plist.exists(), str(tracker_plist)))
    checks.append(("Menubar LaunchAgent", menubar_plist.exists(), str(menubar_plist)))

    # Check 8: Services loaded
    services = [
        ("co.invariante.zeit", "Tracker service"),
        ("co.invariante.zeit.menubar", "Menubar service"),
    ]
    for label, name in services:
        loaded = False
        try:
            result = subprocess.run(["launchctl", "list", label], capture_output=True, text=True)
            loaded = result.returncode == 0
        except FileNotFoundError:
            pass
        checks.append((name, loaded, ""))

    # Display results
    table = Table(title="Zeit System Check")
    table.add_column("Check", style="cyan")
    table.add_column("Status", style="green")
    table.add_column("Details", style="dim")

    all_passed = True
    for check_name, passed, details in checks:
        status = "[green]✓[/green]" if passed else "[red]✗[/red]"
        if not passed:
            all_passed = False
        table.add_row(check_name, status, details)

    rprint(table)

    if all_passed:
        rprint("\n[green]All checks passed![/green]")
    else:
        rprint("\n[yellow]Some checks failed. See details above.[/yellow]")


def main() -> None:
    """CLI entry point."""
    app()


if __name__ == "__main__":
    main()
