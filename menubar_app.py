#!/usr/bin/env python3
"""Zeit Menu Bar App - Shows today's activity summary in macOS menu bar."""

import rumps  # type: ignore[import-untyped]
import logging
from datetime import datetime
from pathlib import Path
from db import DatabaseManager, DayRecord
from activity_summarization import compute_summary
from config import get_config, is_within_work_hours

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

class TrackingState:
    icon: str
    status_message: str
    can_toggle: bool
    def __init__(self, icon: str, status_message: str, can_toggle: bool):
        self.icon = icon
        self.status_message = status_message
        self.can_toggle = can_toggle
    @classmethod
    def not_within_work_hours(cls, status_message: str):
        return cls(icon="🌙", status_message=status_message, can_toggle=False)
    
    @classmethod
    def paused_manual(cls):
        return cls(icon="⏸️", status_message="Tracking paused (manual)", can_toggle=True)
    
    @classmethod
    def active(cls):
        return cls(icon="📊", status_message="Tracking active", can_toggle=True)

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

    def get_tracking_state(self) -> TrackingState:
        """
        Determine current tracking state.

        Returns:
            Tuple of (icon, status_message, can_toggle)
            - icon: Emoji to display in menu bar
            - status_message: Description of current state
            - can_toggle: Whether toggle button should be enabled
        """
        within_work_hours = is_within_work_hours()
        manually_stopped = self.STOP_FLAG.exists()

        if not within_work_hours:
            # Outside work hours - highest priority
            config = get_config()
            status = config.work_hours.get_status_message()
            return TrackingState.not_within_work_hours(status)

        elif manually_stopped:
            # Manually paused during work hours
            return TrackingState.paused_manual()

        else:
            # Active tracking during work hours
            return TrackingState.active()
    
    def toggle_tracking(self, _):
        """Toggle tracking on/off by creating/removing the flag file."""
        # Check if we're in work hours first
        if not is_within_work_hours():
            config = get_config()
            status_msg = config.work_hours.get_status_message()
            logger.info("Cannot toggle tracking outside work hours")
            rumps.notification(
                title="Zeit Tracking",
                subtitle="Outside Work Hours",
                message=status_msg
            )
            return

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
        # Get tracking state first
        tracking_state = self.get_tracking_state()

        today = datetime.now().strftime("%Y-%m-%d")
        logger.debug(f"Updating menu for {today} - State: {tracking_state.status_message}")

        with DatabaseManager() as db:
            day_record = db.get_day_record(today)

            if day_record is None or len(day_record.activities) == 0:
                self._update_menu_no_data(today, tracking_state)
            else:
                self._update_menu_with_data(day_record, today, tracking_state)

    def _update_menu_no_data(self, today: str, tracking_state: TrackingState):
        """Update menu when there's no data for today."""
        self.title = tracking_state.icon

        # Determine toggle text and callback
        if tracking_state.can_toggle:
            is_active = self.is_tracking_active()
            toggle_text = "⏸️ Stop Tracking" if is_active else "▶️ Resume Tracking"
            toggle_callback = self.toggle_tracking
        else:
            toggle_text = "▶️ Resume Tracking (disabled)"
            toggle_callback = None

        toggle_item = rumps.MenuItem(toggle_text, callback=toggle_callback)

        self.menu.clear()
        self.menu = [
            rumps.MenuItem(f"{today}", callback=None),
            rumps.MenuItem("No activities tracked yet", callback=None),
            rumps.MenuItem(tracking_state.status_message, callback=None),
            rumps.separator,
            toggle_item,
            rumps.separator,
            rumps.MenuItem("Refresh", callback=self.refresh),
            rumps.MenuItem("View Details", callback=self.view_details),
            rumps.separator,
            rumps.MenuItem("Quit", callback=self.quit_app)
        ]

    def _update_menu_with_data(self, day_record: DayRecord, today: str, tracking_state: TrackingState):
        """Update menu with activity summary data."""
        summary = compute_summary(day_record.activities)
        total_count = len(day_record.activities)

        # Calculate work percentage
        work_percentage = sum(
            entry.percentage
            for entry in summary
            if entry.activity.is_work_activity()
        )

        # Update title with icon and percentage
        self.title = f"{tracking_state.icon} {work_percentage:.0f}%"

        # Determine toggle text and callback
        if tracking_state.can_toggle:
            is_active = self.is_tracking_active()
            toggle_text = "⏸️ Stop Tracking" if is_active else "▶️ Resume Tracking"
            toggle_callback = self.toggle_tracking
        else:
            toggle_text = "▶️ Resume Tracking (disabled)"
            toggle_callback = None

        toggle_item = rumps.MenuItem(toggle_text, callback=toggle_callback)

        # Build menu items
        menu_items = [
            rumps.MenuItem(f"{today} ({total_count} activities)", callback=None),
            rumps.MenuItem(tracking_state.status_message, callback=None),
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
            toggle_item,
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
                    details: list[str] = []
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
