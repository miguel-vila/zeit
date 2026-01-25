#!/usr/bin/env python3
"""Service management CLI commands for Zeit."""

import os
import plistlib
import subprocess
from pathlib import Path
from typing import Annotated

import typer
from rich import print as rprint

from zeit.core.config import get_config

app = typer.Typer(
    name="service",
    help="Manage Zeit background services",
    add_completion=False,
)

# Service constants
TRACKER_LABEL = "co.invariante.zeit"
MENUBAR_LABEL = "co.invariante.zeit.menubar"
LAUNCH_AGENTS_DIR = Path.home() / "Library" / "LaunchAgents"
LOG_DIR = Path.home() / "Library" / "Logs" / "zeit"
DATA_DIR = Path.home() / ".local" / "share" / "zeit"


def _get_domain() -> str:
    """Get the launchd domain for current user."""
    return f"gui/{os.getuid()}"


def _get_plist_path(label: str) -> Path:
    """Get plist file path for a service label."""
    return LAUNCH_AGENTS_DIR / f"{label}.plist"


def _is_service_loaded(label: str) -> bool:
    """Check if a service is loaded in launchd."""
    result = subprocess.run(
        ["launchctl", "list", label],
        capture_output=True,
        text=True,
    )
    return result.returncode == 0


def _bootstrap_service(plist_path: Path) -> bool:
    """Load service using launchctl bootstrap."""
    try:
        subprocess.run(
            ["launchctl", "bootstrap", _get_domain(), str(plist_path)],
            check=True,
            capture_output=True,
            text=True,
        )
        return True
    except subprocess.CalledProcessError as e:
        if "already bootstrapped" in e.stderr.lower():
            return True
        rprint(f"[red]Failed to bootstrap service: {e.stderr}[/red]")
        return False


def _bootout_service(plist_path: Path, label: str) -> bool:
    """Unload service using launchctl bootout."""
    try:
        subprocess.run(
            ["launchctl", "bootout", _get_domain(), str(plist_path)],
            check=True,
            capture_output=True,
            text=True,
        )
        return True
    except subprocess.CalledProcessError as e:
        if "not found" in e.stderr.lower() or "no such" in e.stderr.lower():
            return True
        rprint(f"[red]Failed to bootout service: {e.stderr}[/red]")
        return False


def _kickstart_service(label: str) -> bool:
    """Start service immediately."""
    try:
        subprocess.run(
            ["launchctl", "kickstart", "-k", f"{_get_domain()}/{label}"],
            check=True,
            capture_output=True,
            text=True,
        )
        return True
    except subprocess.CalledProcessError as e:
        rprint(f"[red]Failed to start service: {e.stderr}[/red]")
        return False


def _create_tracker_plist(cli_path: Path) -> dict:
    """Create plist data for tracker service."""
    return {
        "Label": TRACKER_LABEL,
        "ProgramArguments": [str(cli_path), "track"],
        "WorkingDirectory": str(DATA_DIR),
        "StartInterval": 60,
        "RunAtLoad": True,
        "KeepAlive": False,
        "StandardOutPath": str(LOG_DIR / "tracker.out.log"),
        "StandardErrorPath": str(LOG_DIR / "tracker.err.log"),
        "EnvironmentVariables": {
            "PATH": "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": str(Path.home()),
        },
    }


def _create_menubar_plist(app_path: Path) -> dict:
    """Create plist data for menubar app."""
    executable = app_path / "Contents" / "MacOS" / "Zeit" if app_path.suffix == ".app" else app_path

    return {
        "Label": MENUBAR_LABEL,
        "ProgramArguments": [str(executable)],
        "WorkingDirectory": str(DATA_DIR),
        "RunAtLoad": True,
        "KeepAlive": {"SuccessfulExit": False},
        "ProcessType": "Interactive",
        "StandardOutPath": str(LOG_DIR / "menubar.out.log"),
        "StandardErrorPath": str(LOG_DIR / "menubar.err.log"),
        "EnvironmentVariables": {
            "PATH": "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": str(Path.home()),
        },
    }


def _write_plist(plist_data: dict, plist_path: Path) -> bool:
    """Write plist file and validate it."""
    plist_path.parent.mkdir(parents=True, exist_ok=True)

    with open(plist_path, "wb") as f:
        plistlib.dump(plist_data, f)

    result = subprocess.run(
        ["plutil", "-lint", str(plist_path)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        rprint(f"[red]Invalid plist: {result.stderr}[/red]")
        return False
    return True


@app.command("status")
def status() -> None:
    """Show status of Zeit services."""
    rprint("\n[bold]Zeit Service Status[/bold]")
    rprint("-" * 40)

    for label, name in [(TRACKER_LABEL, "Tracker"), (MENUBAR_LABEL, "Menubar")]:
        plist_path = _get_plist_path(label)
        plist_exists = plist_path.exists()
        is_loaded = _is_service_loaded(label)

        if is_loaded:
            status_str = "[green]running[/green]"
        elif plist_exists:
            status_str = "[yellow]stopped[/yellow]"
        else:
            status_str = "[dim]not installed[/dim]"

        rprint(f"  {name}: {status_str}")

    # Check stop flag
    config = get_config()
    stop_flag = config.paths.stop_flag
    if stop_flag.exists():
        rprint(f"\n[yellow]Tracking paused[/yellow] (stop flag: {stop_flag})")
    else:
        rprint("\n[green]Tracking active[/green]")


@app.command("stop")
def stop() -> None:
    """Pause tracking by creating stop flag file."""
    config = get_config()
    stop_flag = config.paths.stop_flag

    if stop_flag.exists():
        rprint(f"[yellow]Tracking already paused[/yellow] ({stop_flag})")
        return

    stop_flag.touch()
    rprint(f"[green]✓[/green] Tracking paused (created {stop_flag})")


@app.command("start")
def start() -> None:
    """Resume tracking by removing stop flag file."""
    config = get_config()
    stop_flag = config.paths.stop_flag

    if not stop_flag.exists():
        rprint("[yellow]Tracking is not paused[/yellow]")
        return

    stop_flag.unlink()
    rprint(f"[green]✓[/green] Tracking resumed (removed {stop_flag})")


@app.command("install")
def install(
    cli_path: Annotated[
        Path | None, typer.Option("--cli", help="Path to zeit CLI binary (for tracker service)")
    ] = None,
    app_path: Annotated[
        Path | None, typer.Option("--app", help="Path to Zeit.app (for menubar service)")
    ] = None,
) -> None:
    """Install LaunchAgents for Zeit services."""
    if cli_path is None and app_path is None:
        rprint("[yellow]Specify --cli and/or --app to install[/yellow]")
        raise typer.Exit(1)

    # Ensure directories exist
    LAUNCH_AGENTS_DIR.mkdir(parents=True, exist_ok=True)
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    DATA_DIR.mkdir(parents=True, exist_ok=True)

    if cli_path:
        if not cli_path.exists():
            rprint(f"[red]CLI binary not found: {cli_path}[/red]")
            raise typer.Exit(1)

        plist_path = _get_plist_path(TRACKER_LABEL)

        # Unload if already loaded
        if plist_path.exists():
            _bootout_service(plist_path, TRACKER_LABEL)

        plist_data = _create_tracker_plist(cli_path)
        if not _write_plist(plist_data, plist_path):
            raise typer.Exit(1)

        if _bootstrap_service(plist_path):
            rprint(f"[green]✓[/green] Installed tracker service: {TRACKER_LABEL}")
        else:
            raise typer.Exit(1)

    if app_path:
        if not app_path.exists():
            rprint(f"[red]App not found: {app_path}[/red]")
            raise typer.Exit(1)

        plist_path = _get_plist_path(MENUBAR_LABEL)

        if plist_path.exists():
            _bootout_service(plist_path, MENUBAR_LABEL)

        plist_data = _create_menubar_plist(app_path)
        if not _write_plist(plist_data, plist_path):
            raise typer.Exit(1)

        if _bootstrap_service(plist_path):
            _kickstart_service(MENUBAR_LABEL)
            rprint(f"[green]✓[/green] Installed menubar service: {MENUBAR_LABEL}")
        else:
            raise typer.Exit(1)


@app.command("uninstall")
def uninstall() -> None:
    """Remove all Zeit LaunchAgents."""
    for label in [TRACKER_LABEL, MENUBAR_LABEL]:
        plist_path = _get_plist_path(label)
        if plist_path.exists():
            _bootout_service(plist_path, label)
            plist_path.unlink()
            rprint(f"[green]✓[/green] Removed service: {label}")
        else:
            rprint(f"[dim]Service not installed: {label}[/dim]")


@app.command("restart")
def restart() -> None:
    """Restart the tracker service."""
    if not _is_service_loaded(TRACKER_LABEL):
        rprint("[yellow]Tracker service not running[/yellow]")
        return

    if _kickstart_service(TRACKER_LABEL):
        rprint("[green]✓[/green] Restarted tracker service")
