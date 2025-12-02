#!/usr/bin/env python3
"""Zeit Menu Bar App - Shows today's activity summary in macOS menu bar."""

import rumps
import logging
import os
from datetime import datetime
from pathlib import Path
from db import DatabaseManager
from activity_summarization import compute_summary

# Configure logging
log_dir = Path("logs")
log_dir.mkdir(parents=True, exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(log_dir / "menubar.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)


class ZeitMenuBar(rumps.App):
    """Menu bar application for Zeit activity tracker."""

    STOP_FLAG = Path.home() / ".zeit_stop"

    def __init__(self):
        super().__init__("📊", quit_button=None)
        logger.info("Starting Zeit Menu Bar App")

        # Initialize menu structure
        self.menu = [
            rumps.MenuItem("Loading...", callback=None),
            rumps.separator,
            rumps.MenuItem("Refresh", callback=self.refresh),
            rumps.MenuItem("View Details", callback=self.view_details),
            rumps.separator,
            rumps.MenuItem("Quit", callback=self.quit_app)
        ]

        # Initial update
        self.update_menu()

    def is_tracking_active(self):
        """Check if tracking is currently active (flag file doesn't exist)."""
        return not self.STOP_FLAG.exists()

    def toggle_tracking(self, _):
        """Toggle tracking on/off by creating/removing the flag file."""
        try:
            if self.is_tracking_active():
                # Stop tracking
                self.STOP_FLAG.touch()
                logger.info("Tracking stopped via menu bar toggle")
                rumps.notification(
                    title="Zeit Tracking",
                    subtitle="Stopped",
                    message="Tracking has been paused"
                )
            else:
                # Resume tracking
                self.STOP_FLAG.unlink()
                logger.info("Tracking resumed via menu bar toggle")
                rumps.notification(
                    title="Zeit Tracking",
                    subtitle="Resumed",
                    message="Tracking has been resumed"
                )

            # Update menu to reflect new status
            self.update_menu()
        except Exception as e:
            logger.error(f"Error toggling tracking: {e}", exc_info=True)
            rumps.notification(
                title="Zeit Error",
                subtitle="Toggle Failed",
                message=str(e)
            )

    @rumps.timer(60)  # Update every 60 seconds
    def update_menu(self, _=None):
        """Update the menu with current activity data."""
        try:
            today = datetime.now().strftime("%Y-%m-%d")
            logger.debug(f"Updating menu for {today}")

            with DatabaseManager() as db:
                day_record = db.get_day_record(today)

                if day_record is None or len(day_record.activities) == 0:
                    self._update_menu_no_data(today)
                else:
                    self._update_menu_with_data(day_record, today)

        except Exception as e:
            logger.error(f"Error updating menu: {e}", exc_info=True)
            tracking_active = self.is_tracking_active()
            self.title = "📊" if tracking_active else "⏸️"
            toggle_text = "⏸️ Stop Tracking" if tracking_active else "▶️ Resume Tracking"

            self.menu.clear()
            self.menu = [
                rumps.MenuItem(f"Error: {str(e)}", callback=None),
                rumps.separator,
                rumps.MenuItem(toggle_text, callback=self.toggle_tracking),
                rumps.separator,
                rumps.MenuItem("Refresh", callback=self.refresh),
                rumps.MenuItem("Quit", callback=self.quit_app)
            ]

    def _update_menu_no_data(self, today):
        """Update menu when there's no data for today."""
        tracking_active = self.is_tracking_active()
        self.title = "📊" if tracking_active else "⏸️"

        toggle_text = "⏸️ Stop Tracking" if tracking_active else "▶️ Resume Tracking"

        self.menu.clear()
        self.menu = [
            rumps.MenuItem(f"{today}", callback=None),
            rumps.MenuItem("No activities tracked yet", callback=None),
            rumps.separator,
            rumps.MenuItem(toggle_text, callback=self.toggle_tracking),
            rumps.separator,
            rumps.MenuItem("Refresh", callback=self.refresh),
            rumps.MenuItem("View Details", callback=self.view_details),
            rumps.separator,
            rumps.MenuItem("Quit", callback=self.quit_app)
        ]

    def _update_menu_with_data(self, day_record, today):
        """Update menu with activity summary data."""
        summary = compute_summary(day_record.activities)
        total_count = len(day_record.activities)
        tracking_active = self.is_tracking_active()

        # Update title with work percentage if work activities exist
        work_percentage = sum(
            entry.percentage
            for entry in summary
            if entry.activity.is_work_activity()
        )

        if tracking_active:
            self.title = f"📊 {work_percentage:.0f}%"
        else:
            self.title = f"⏸️ {work_percentage:.0f}%"

        toggle_text = "⏸️ Stop Tracking" if tracking_active else "▶️ Resume Tracking"

        # Build menu items
        menu_items = [
            rumps.MenuItem(f"{today} ({total_count} activities)", callback=None),
            rumps.separator,
        ]

        # Add activity breakdown
        for entry in summary:
            activity_name = entry.activity.value.replace('_', ' ').title()
            percentage = entry.percentage
            menu_items.append(
                rumps.MenuItem(f"{activity_name}: {percentage:.1f}%", callback=None)
            )

        # Add controls
        menu_items.extend([
            rumps.separator,
            rumps.MenuItem(toggle_text, callback=self.toggle_tracking),
            rumps.separator,
            rumps.MenuItem("Refresh", callback=self.refresh),
            rumps.MenuItem("View Details", callback=self.view_details),
            rumps.separator,
            rumps.MenuItem("Quit", callback=self.quit_app)
        ])

        # Update menu
        self.menu.clear()
        self.menu = menu_items

    def refresh(self, _):
        """Manually refresh the menu data."""
        logger.info("Manual refresh triggered")
        rumps.notification(
            title="Zeit",
            subtitle="Refreshing...",
            message="Updating activity data"
        )
        self.update_menu()

    def view_details(self, _):
        """Open a notification with more details or trigger external viewer."""
        try:
            today = datetime.now().strftime("%Y-%m-%d")
            with DatabaseManager() as db:
                day_record = db.get_day_record(today)

                if day_record and len(day_record.activities) > 0:
                    summary = compute_summary(day_record.activities)

                    # Build detailed message
                    details = []
                    for entry in summary:
                        activity_name = entry.activity.value.replace('_', ' ').title()
                        details.append(f"{activity_name}: {entry.percentage:.1f}%")

                    message = "\n".join(details)

                    rumps.notification(
                        title="Zeit Activity Summary",
                        subtitle=f"{today} - {len(day_record.activities)} activities",
                        message=message
                    )
                else:
                    rumps.notification(
                        title="Zeit",
                        subtitle="No Data",
                        message=f"No activities tracked for {today}"
                    )
        except Exception as e:
            logger.error(f"Error viewing details: {e}", exc_info=True)
            rumps.notification(
                title="Zeit Error",
                subtitle="Failed to load details",
                message=str(e)
            )

    def quit_app(self, _):
        """Quit the application."""
        logger.info("Quitting Zeit Menu Bar App")
        rumps.quit_application()


def main():
    """Main entry point."""
    try:
        app = ZeitMenuBar()
        app.run()
    except Exception as e:
        logger.error(f"Failed to start menu bar app: {e}", exc_info=True)
        raise


if __name__ == "__main__":
    main()
