#!/usr/bin/env python3
"""
Zeit Installation Script

Installs Zeit CLI, menubar app, and LaunchAgents.
No sudo required - installs to user directories.

Usage:
    python scripts/install.py install --cli dist/zeit --app dist/Zeit.app
    python scripts/install.py uninstall
    python scripts/install.py status
"""

import argparse
import os
import plistlib
import shutil
import subprocess
import sys
from pathlib import Path


class ZeitInstaller:
    """Manages Zeit installation and LaunchAgent setup."""

    # Installation paths
    DEFAULT_INSTALL_DIR = Path.home() / ".local" / "bin"
    LAUNCH_AGENTS_DIR = Path.home() / "Library" / "LaunchAgents"
    LOG_DIR = Path.home() / "Library" / "Logs" / "zeit"
    DATA_DIR = Path.home() / ".local" / "share" / "zeit"

    # Service labels
    TRACKER_LABEL = "co.invariante.zeit"
    MENUBAR_LABEL = "co.invariante.zeit.menubar"

    def __init__(self) -> None:
        """Initialize installer."""
        self.user_id = os.getuid()
        self.domain = f"gui/{self.user_id}"

    def _ensure_directories(self) -> None:
        """Create required directories."""
        self.DEFAULT_INSTALL_DIR.mkdir(parents=True, exist_ok=True)
        self.LAUNCH_AGENTS_DIR.mkdir(parents=True, exist_ok=True)
        self.LOG_DIR.mkdir(parents=True, exist_ok=True)
        self.DATA_DIR.mkdir(parents=True, exist_ok=True)

    def _get_plist_path(self, label: str) -> Path:
        """Get plist file path for a service label."""
        return self.LAUNCH_AGENTS_DIR / f"{label}.plist"

    def _create_tracker_plist(self, cli_path: Path) -> dict:
        """Create plist data for tracker service."""
        return {
            "Label": self.TRACKER_LABEL,
            "ProgramArguments": [str(cli_path), "track"],
            "WorkingDirectory": str(self.DATA_DIR),
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
            "WorkingDirectory": str(self.DATA_DIR),
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
            print(f"Warning: Failed to bootstrap service: {e.stderr}")
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
            print(f"Warning: Failed to bootout service: {e.stderr}")
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
            print(f"Warning: Failed to start service: {e.stderr}")
            return False

    def _is_service_loaded(self, label: str) -> bool:
        """Check if a service is loaded."""
        result = subprocess.run(
            ["launchctl", "list", label],
            capture_output=True,
            text=True,
        )
        return result.returncode == 0

    def install_cli(self, cli_binary: Path) -> Path:
        """Install CLI binary to user bin directory."""
        self._ensure_directories()

        dest_path = self.DEFAULT_INSTALL_DIR / "zeit"

        if cli_binary.exists():
            shutil.copy2(cli_binary, dest_path)
            dest_path.chmod(0o755)
            print(f"Installed CLI to: {dest_path}")
        else:
            raise FileNotFoundError(f"CLI binary not found: {cli_binary}")

        return dest_path

    def install_app(self, app_path: Path, to_applications: bool = False) -> Path:
        """Install menubar app."""
        if to_applications:
            dest_path = Path("/Applications/Zeit.app")
            if dest_path.exists():
                shutil.rmtree(dest_path)
            shutil.copytree(app_path, dest_path)
            print(f"Installed app to: {dest_path}")
        else:
            dest_path = app_path
            print(f"Using app at: {dest_path}")

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
            print(f"Installed tracker service: {self.TRACKER_LABEL}")

    def install_menubar_service(self, app_path: Path) -> None:
        """Install menubar LaunchAgent (starts on login)."""
        self._ensure_directories()

        plist_path = self._get_plist_path(self.MENUBAR_LABEL)
        plist_data = self._create_menubar_plist(app_path)

        if plist_path.exists():
            self._bootout_service(plist_path, self.MENUBAR_LABEL)

        self._write_plist(plist_data, plist_path)

        if self._bootstrap_service(plist_path):
            self._kickstart_service(self.MENUBAR_LABEL)
            print(f"Installed menubar service: {self.MENUBAR_LABEL}")

    def uninstall_services(self) -> None:
        """Uninstall all LaunchAgents."""
        for label in [self.TRACKER_LABEL, self.MENUBAR_LABEL]:
            plist_path = self._get_plist_path(label)
            if plist_path.exists():
                self._bootout_service(plist_path, label)
                plist_path.unlink()
                print(f"Removed service: {label}")

    def uninstall_cli(self) -> None:
        """Remove CLI binary."""
        cli_path = self.DEFAULT_INSTALL_DIR / "zeit"
        if cli_path.exists():
            cli_path.unlink()
            print(f"Removed CLI: {cli_path}")

    def uninstall_all(self, remove_data: bool = False) -> None:
        """Complete uninstallation."""
        self.uninstall_services()
        self.uninstall_cli()

        if remove_data:
            if self.LOG_DIR.exists():
                shutil.rmtree(self.LOG_DIR)
                print(f"Removed logs: {self.LOG_DIR}")
            if self.DATA_DIR.exists():
                shutil.rmtree(self.DATA_DIR)
                print(f"Removed data: {self.DATA_DIR}")

    def get_status(self) -> dict[str, dict[str, bool | str | None]]:
        """Get status of all services."""
        status: dict[str, dict[str, bool | str | None]] = {}

        for label in [self.TRACKER_LABEL, self.MENUBAR_LABEL]:
            status[label] = {
                "loaded": self._is_service_loaded(label),
                "plist_exists": self._get_plist_path(label).exists(),
            }

        cli_path = self.DEFAULT_INSTALL_DIR / "zeit"
        status_cli: dict[str, bool | str | None] = {
            "installed": cli_path.exists(),
            "path": str(cli_path) if cli_path.exists() else None,
        }
        status["cli"] = status_cli

        return status


def main() -> None:
    """CLI entry point for installer."""
    parser = argparse.ArgumentParser(description="Install Zeit activity tracker")
    parser.add_argument(
        "action",
        choices=["install", "uninstall", "status"],
        help="Action to perform",
    )
    parser.add_argument("--cli", type=Path, help="Path to zeit CLI binary")
    parser.add_argument("--app", type=Path, help="Path to Zeit.app")
    parser.add_argument(
        "--to-applications",
        action="store_true",
        help="Copy app to /Applications",
    )
    parser.add_argument(
        "--remove-data",
        action="store_true",
        help="Also remove data when uninstalling",
    )

    args = parser.parse_args()

    installer = ZeitInstaller()

    if args.action == "install":
        if args.cli:
            cli_path = installer.install_cli(args.cli)
            installer.install_tracker_service(cli_path)

        if args.app:
            app_path = installer.install_app(args.app, args.to_applications)
            installer.install_menubar_service(app_path)

        if not args.cli and not args.app:
            print("Error: Specify --cli and/or --app to install")
            sys.exit(1)

        print("\nInstallation complete!")
        print(f"Add {installer.DEFAULT_INSTALL_DIR} to your PATH if not already.")

    elif args.action == "uninstall":
        installer.uninstall_all(remove_data=args.remove_data)
        print("\nUninstallation complete!")

    elif args.action == "status":
        status = installer.get_status()
        print("\nZeit Installation Status:")
        print("-" * 40)
        for key, value in status.items():
            print(f"{key}: {value}")


if __name__ == "__main__":
    main()
