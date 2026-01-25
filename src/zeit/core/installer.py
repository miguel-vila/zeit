"""
Zeit Installer Module

Provides installation logic for first-run setup and programmatic installation.
Extracted from scripts/install.py for use within the app bundle.
"""

import logging
import os
import plistlib
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path

from zeit.core.config import DATA_DIR

logger = logging.getLogger(__name__)


class SetupStep(Enum):
    """Steps in the setup process."""

    CLI_INSTALL = "cli_install"
    TRACKER_SERVICE = "tracker_service"
    MENUBAR_SERVICE = "menubar_service"
    MARK_COMPLETE = "mark_complete"


@dataclass
class SetupResult:
    """Result of a setup operation."""

    success: bool
    message: str
    steps_completed: list[SetupStep] = field(default_factory=list)
    error: str | None = None


class ZeitInstaller:
    """Manages Zeit installation and LaunchAgent setup."""

    # Installation paths
    INSTALL_DIR = Path.home() / ".local" / "bin"
    LAUNCH_AGENTS_DIR = Path.home() / "Library" / "LaunchAgents"
    LOG_DIR = Path.home() / "Library" / "Logs" / "zeit"
    SETUP_MARKER = DATA_DIR / ".setup_complete"

    # Service labels
    TRACKER_LABEL = "co.invariante.zeit"
    MENUBAR_LABEL = "co.invariante.zeit.menubar"

    def __init__(self) -> None:
        """Initialize installer."""
        self.user_id = os.getuid()
        self.domain = f"gui/{self.user_id}"

    def is_setup_complete(self) -> bool:
        """Check if first-run setup has been completed."""
        return self.SETUP_MARKER.exists()

    def mark_setup_complete(self) -> None:
        """Mark setup as complete by creating the marker file."""
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        self.SETUP_MARKER.touch()
        logger.info(f"Setup marked complete: {self.SETUP_MARKER}")

    def get_bundled_cli_path(self) -> Path | None:
        """
        Find the CLI binary bundled within the app.

        Returns:
            Path to bundled CLI, or None if not found or not running from app bundle.
        """
        # When running from a .app bundle, sys.executable is inside the bundle
        # e.g., /Applications/Zeit.app/Contents/MacOS/Zeit
        executable = Path(sys.executable)

        # Check if we're in a .app bundle
        if ".app" not in str(executable):
            logger.debug("Not running from .app bundle")
            return None

        # Navigate to Contents/Resources/bin/zeit
        # From MacOS/Zeit -> Contents/Resources/bin/zeit
        contents_dir = executable.parent.parent
        bundled_cli = contents_dir / "Resources" / "bin" / "zeit"

        if bundled_cli.exists():
            logger.debug(f"Found bundled CLI: {bundled_cli}")
            return bundled_cli

        logger.debug(f"Bundled CLI not found at: {bundled_cli}")
        return None

    def get_app_bundle_path(self) -> Path | None:
        """
        Get the path to the current app bundle.

        Returns:
            Path to the .app bundle, or None if not running from a bundle.
        """
        executable = Path(sys.executable)

        # Find the .app directory
        for parent in executable.parents:
            if parent.suffix == ".app":
                return parent

        return None

    def _ensure_directories(self) -> None:
        """Create required directories."""
        self.INSTALL_DIR.mkdir(parents=True, exist_ok=True)
        self.LAUNCH_AGENTS_DIR.mkdir(parents=True, exist_ok=True)
        self.LOG_DIR.mkdir(parents=True, exist_ok=True)
        DATA_DIR.mkdir(parents=True, exist_ok=True)

    def _get_plist_path(self, label: str) -> Path:
        """Get plist file path for a service label."""
        return self.LAUNCH_AGENTS_DIR / f"{label}.plist"

    def _create_tracker_plist(self, cli_path: Path) -> dict:
        """Create plist data for tracker service."""
        return {
            "Label": self.TRACKER_LABEL,
            "ProgramArguments": [str(cli_path), "track"],
            "WorkingDirectory": str(DATA_DIR),
            "StartInterval": 60,
            "RunAtLoad": True,
            "KeepAlive": False,
            "StandardOutPath": str(self.LOG_DIR / "tracker.out.log"),
            "StandardErrorPath": str(self.LOG_DIR / "tracker.err.log"),
            "EnvironmentVariables": {
                "PATH": "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                "HOME": str(Path.home()),
            },
        }

    def _create_menubar_plist(self, app_path: Path) -> dict:
        """Create plist data for menubar app."""
        executable = (
            app_path / "Contents" / "MacOS" / "Zeit" if app_path.suffix == ".app" else app_path
        )

        return {
            "Label": self.MENUBAR_LABEL,
            "ProgramArguments": [str(executable)],
            "WorkingDirectory": str(DATA_DIR),
            "RunAtLoad": True,
            "KeepAlive": {"SuccessfulExit": False},
            "ProcessType": "Interactive",
            "StandardOutPath": str(self.LOG_DIR / "menubar.out.log"),
            "StandardErrorPath": str(self.LOG_DIR / "menubar.err.log"),
            "EnvironmentVariables": {
                "PATH": "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                "HOME": str(Path.home()),
            },
        }

    def _write_plist(self, plist_data: dict, plist_path: Path) -> None:
        """Write plist file and validate it."""
        with open(plist_path, "wb") as f:
            plistlib.dump(plist_data, f)

        result = subprocess.run(
            ["plutil", "-lint", str(plist_path)],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            raise RuntimeError(f"Invalid plist: {result.stderr}")

    def _bootstrap_service(self, plist_path: Path) -> bool:
        """Load service using modern launchctl bootstrap."""
        try:
            subprocess.run(
                ["launchctl", "bootstrap", self.domain, str(plist_path)],
                check=True,
                capture_output=True,
                text=True,
            )
            return True
        except subprocess.CalledProcessError as e:
            if "already bootstrapped" in e.stderr.lower():
                return True
            logger.warning(f"Failed to bootstrap service: {e.stderr}")
            return False

    def _bootout_service(self, plist_path: Path, label: str) -> bool:
        """Unload service using modern launchctl bootout."""
        try:
            subprocess.run(
                ["launchctl", "bootout", self.domain, str(plist_path)],
                check=True,
                capture_output=True,
                text=True,
            )
            return True
        except subprocess.CalledProcessError as e:
            if "not found" in e.stderr.lower() or "no such" in e.stderr.lower():
                return True
            logger.warning(f"Failed to bootout service: {e.stderr}")
            return False

    def _kickstart_service(self, label: str) -> bool:
        """Start service immediately."""
        try:
            subprocess.run(
                ["launchctl", "kickstart", "-k", f"{self.domain}/{label}"],
                check=True,
                capture_output=True,
                text=True,
            )
            return True
        except subprocess.CalledProcessError as e:
            logger.warning(f"Failed to start service: {e.stderr}")
            return False

    def _is_service_loaded(self, label: str) -> bool:
        """Check if a service is loaded."""
        result = subprocess.run(
            ["launchctl", "list", label],
            capture_output=True,
            text=True,
        )
        return result.returncode == 0

    def install_cli(self, source: Path) -> Path:
        """
        Install CLI binary to user bin directory.

        Args:
            source: Path to the CLI binary to install

        Returns:
            Path to the installed CLI binary

        Raises:
            FileNotFoundError: If source binary doesn't exist
        """
        self._ensure_directories()

        if not source.exists():
            raise FileNotFoundError(f"CLI binary not found: {source}")

        dest_path = self.INSTALL_DIR / "zeit"
        shutil.copy2(source, dest_path)
        dest_path.chmod(0o755)

        logger.info(f"Installed CLI to: {dest_path}")
        return dest_path

    def install_app(self, app_path: Path, to_applications: bool = False) -> Path:
        """
        Install menubar app.

        Args:
            app_path: Path to the Zeit.app bundle
            to_applications: If True, copy to /Applications

        Returns:
            Path to the installed/used app
        """
        if to_applications:
            dest_path = Path("/Applications/Zeit.app")
            if dest_path.exists():
                shutil.rmtree(dest_path)
            shutil.copytree(app_path, dest_path)
            logger.info(f"Installed app to: {dest_path}")
        else:
            dest_path = app_path
            logger.info(f"Using app at: {dest_path}")

        return dest_path

    def install_tracker_service(self, cli_path: Path) -> None:
        """Install and start tracker LaunchAgent."""
        self._ensure_directories()

        plist_path = self._get_plist_path(self.TRACKER_LABEL)
        plist_data = self._create_tracker_plist(cli_path)

        if plist_path.exists():
            self._bootout_service(plist_path, self.TRACKER_LABEL)

        self._write_plist(plist_data, plist_path)

        if self._bootstrap_service(plist_path):
            logger.info(f"Installed tracker service: {self.TRACKER_LABEL}")

    def install_menubar_service(self, app_path: Path, kickstart: bool = False) -> None:
        """
        Install menubar LaunchAgent (starts on login).

        Args:
            app_path: Path to the Zeit.app bundle
            kickstart: If True, start the service immediately
        """
        self._ensure_directories()

        plist_path = self._get_plist_path(self.MENUBAR_LABEL)
        plist_data = self._create_menubar_plist(app_path)

        if plist_path.exists():
            self._bootout_service(plist_path, self.MENUBAR_LABEL)

        self._write_plist(plist_data, plist_path)

        if self._bootstrap_service(plist_path):
            if kickstart:
                self._kickstart_service(self.MENUBAR_LABEL)
            logger.info(f"Installed menubar service: {self.MENUBAR_LABEL}")

    def uninstall_services(self) -> None:
        """Uninstall all LaunchAgents."""
        for label in [self.TRACKER_LABEL, self.MENUBAR_LABEL]:
            plist_path = self._get_plist_path(label)
            if plist_path.exists():
                self._bootout_service(plist_path, label)
                plist_path.unlink()
                logger.info(f"Removed service: {label}")

    def uninstall_cli(self) -> None:
        """Remove CLI binary."""
        cli_path = self.INSTALL_DIR / "zeit"
        if cli_path.exists():
            cli_path.unlink()
            logger.info(f"Removed CLI: {cli_path}")

    def uninstall_all(self, remove_data: bool = False) -> None:
        """
        Complete uninstallation.

        Args:
            remove_data: If True, also remove logs and data directory
        """
        self.uninstall_services()
        self.uninstall_cli()

        if remove_data:
            if self.LOG_DIR.exists():
                shutil.rmtree(self.LOG_DIR)
                logger.info(f"Removed logs: {self.LOG_DIR}")
            if DATA_DIR.exists():
                shutil.rmtree(DATA_DIR)
                logger.info(f"Removed data: {DATA_DIR}")

    def run_full_setup(self, skip_menubar_service: bool = True) -> SetupResult:
        """
        Run the full first-time setup.

        Args:
            skip_menubar_service: If True, don't install menubar LaunchAgent
                                  (we're already running, will be installed manually later)

        Returns:
            SetupResult with success status and details
        """
        steps_completed: list[SetupStep] = []

        try:
            # Step 1: Find and install CLI
            bundled_cli = self.get_bundled_cli_path()
            if bundled_cli is None:
                return SetupResult(
                    success=False,
                    message="Setup failed",
                    error="Could not find bundled CLI binary. App may be corrupted.",
                )

            cli_path = self.install_cli(bundled_cli)
            steps_completed.append(SetupStep.CLI_INSTALL)

            # Step 2: Install tracker service
            self.install_tracker_service(cli_path)
            steps_completed.append(SetupStep.TRACKER_SERVICE)

            # Step 3: Install menubar service (optional)
            if not skip_menubar_service:
                app_path = self.get_app_bundle_path()
                if app_path:
                    self.install_menubar_service(app_path)
                    steps_completed.append(SetupStep.MENUBAR_SERVICE)

            # Step 4: Mark setup complete
            self.mark_setup_complete()
            steps_completed.append(SetupStep.MARK_COMPLETE)

            return SetupResult(
                success=True,
                message="Setup completed successfully",
                steps_completed=steps_completed,
            )

        except Exception as e:
            logger.error(f"Setup failed: {e}", exc_info=True)
            return SetupResult(
                success=False,
                message="Setup failed",
                steps_completed=steps_completed,
                error=str(e),
            )

    def get_status(self) -> dict[str, dict[str, bool | str | None]]:
        """Get status of all services."""
        status: dict[str, dict[str, bool | str | None]] = {}

        for label in [self.TRACKER_LABEL, self.MENUBAR_LABEL]:
            status[label] = {
                "loaded": self._is_service_loaded(label),
                "plist_exists": self._get_plist_path(label).exists(),
            }

        cli_path = self.INSTALL_DIR / "zeit"
        status["cli"] = {
            "installed": cli_path.exists(),
            "path": str(cli_path) if cli_path.exists() else None,
        }

        status["setup"] = {
            "complete": self.is_setup_complete(),
            "marker": str(self.SETUP_MARKER),
        }

        return status


# Module-level convenience functions
_installer: ZeitInstaller | None = None


def get_installer() -> ZeitInstaller:
    """Get the singleton installer instance."""
    global _installer
    if _installer is None:
        _installer = ZeitInstaller()
    return _installer


def is_setup_complete() -> bool:
    """Check if first-run setup has been completed."""
    return get_installer().is_setup_complete()


def run_full_setup(skip_menubar_service: bool = True) -> SetupResult:
    """Run the full first-time setup."""
    return get_installer().run_full_setup(skip_menubar_service)
