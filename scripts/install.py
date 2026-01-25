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
import sys
from pathlib import Path

# Add src directory to path so we can import zeit.core.installer
# This allows the script to work both standalone and when zeit is installed
src_path = Path(__file__).parent.parent / "src"
if str(src_path) not in sys.path:
    sys.path.insert(0, str(src_path))

from zeit.core.installer import ZeitInstaller  # noqa: E402


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
            print(f"Installed CLI to: {cli_path}")
            installer.install_tracker_service(cli_path)
            print(f"Installed tracker service: {installer.TRACKER_LABEL}")

        if args.app:
            app_path = installer.install_app(args.app, args.to_applications)
            print(f"Using app at: {app_path}")
            installer.install_menubar_service(app_path, kickstart=True)
            print(f"Installed menubar service: {installer.MENUBAR_LABEL}")

        if not args.cli and not args.app:
            print("Error: Specify --cli and/or --app to install")
            sys.exit(1)

        print("\nInstallation complete!")
        print(f"Add {installer.INSTALL_DIR} to your PATH if not already.")

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
