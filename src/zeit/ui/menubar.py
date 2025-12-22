#!/usr/bin/env python3
"""Zeit Menu Bar App - PySide6 implementation for macOS menu bar."""

import sys
import logging
from datetime import datetime
from pathlib import Path
from PySide6.QtWidgets import QApplication, QSystemTrayIcon, QMenu
from PySide6.QtCore import QTimer, Slot
from PySide6.QtGui import QAction

from src.zeit.data.db import DatabaseManager, DayRecord
from src.zeit.processing.activity_summarization import compute_summary
from src.zeit.core.config import get_config, is_within_work_hours
from src.zeit.ui.qt_helpers import emoji_to_qicon, show_macos_notification

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
    """Represents the current tracking state."""

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


class ZeitMenuBar:
    """Menu bar application for Zeit activity tracker using PySide6."""

    STOP_FLAG = Path.home() / ".zeit_stop"

    def __init__(self, app: QApplication):
        logger.info("Starting Zeit Menu Bar App (PySide6)")

        self.app = app
        self.tray_icon = QSystemTrayIcon()

        # Set initial icon
        icon = emoji_to_qicon("📊")
        self.tray_icon.setIcon(icon)
        self.tray_icon.setVisible(True)

        # Create menu
        self.menu = QMenu()
        self.tray_icon.setContextMenu(self.menu)

        # Set up timer for periodic updates (60 seconds)
        self.timer = QTimer()
        self.timer.timeout.connect(self.update_menu)
        self.timer.start(60000)  # 60000 ms = 60 seconds

        # Initial menu update
        self.update_menu()

    def is_tracking_active(self) -> bool:
        """Check if tracking is currently active (flag file doesn't exist)."""
        return not self.STOP_FLAG.exists()

    def get_tracking_state(self) -> TrackingState:
        """
        Determine current tracking state.

        Returns:
            TrackingState with icon, status_message, and can_toggle flag
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

    @Slot()
    def toggle_tracking(self):
        """Toggle tracking on/off by creating/removing the flag file."""
        # Check if we're in work hours first
        if not is_within_work_hours():
            config = get_config()
            status_msg = config.work_hours.get_status_message()
            logger.info("Cannot toggle tracking outside work hours")
            show_macos_notification(
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
                show_macos_notification(
                    title="Zeit Tracking",
                    subtitle="Stopped",
                    message="Tracking has been paused"
                )
            else:
                # Resume tracking
                self.STOP_FLAG.unlink()
                logger.info("Tracking resumed via menu bar toggle")
                show_macos_notification(
                    title="Zeit Tracking",
                    subtitle="Resumed",
                    message="Tracking has been resumed"
                )

            # Update menu to reflect new status
            self.update_menu()
        except Exception as e:
            logger.error(f"Error toggling tracking: {e}", exc_info=True)
            show_macos_notification(
                title="Zeit Error",
                subtitle="Toggle Failed",
                message=str(e)
            )

    @Slot()
    def update_menu(self):
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
        # Update icon
        icon = emoji_to_qicon(tracking_state.icon)
        self.tray_icon.setIcon(icon)

        # Clear menu and rebuild
        self.menu.clear()

        # Add static items
        date_action = QAction(f"{today}", self.menu)
        date_action.setEnabled(False)
        self.menu.addAction(date_action)

        no_data_action = QAction("No activities tracked yet", self.menu)
        no_data_action.setEnabled(False)
        self.menu.addAction(no_data_action)

        status_action = QAction(tracking_state.status_message, self.menu)
        status_action.setEnabled(False)
        self.menu.addAction(status_action)

        self.menu.addSeparator()

        # Toggle action
        if tracking_state.can_toggle:
            is_active = self.is_tracking_active()
            toggle_text = "⏸️ Stop Tracking" if is_active else "▶️ Resume Tracking"
            toggle_action = QAction(toggle_text, self.menu)
            toggle_action.triggered.connect(self.toggle_tracking)
            self.menu.addAction(toggle_action)
        else:
            toggle_action = QAction("▶️ Resume Tracking (disabled)", self.menu)
            toggle_action.setEnabled(False)
            self.menu.addAction(toggle_action)

        self.menu.addSeparator()

        # Refresh action
        refresh_action = QAction("Refresh", self.menu)
        refresh_action.triggered.connect(self.refresh)
        self.menu.addAction(refresh_action)

        # View details action
        details_action = QAction("View Details", self.menu)
        details_action.triggered.connect(self.view_details)
        self.menu.addAction(details_action)

        self.menu.addSeparator()

        # Quit action
        quit_action = QAction("Quit", self.menu)
        quit_action.triggered.connect(self.quit_app)
        self.menu.addAction(quit_action)

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

        # Update icon with percentage
        # For now, use emoji. Could enhance to render text with emoji
        icon = emoji_to_qicon(tracking_state.icon)
        self.tray_icon.setIcon(icon)
        self.tray_icon.setToolTip(f"{work_percentage:.0f}%")

        # Clear menu and rebuild
        self.menu.clear()

        # Add header
        header_action = QAction(f"{today} ({total_count} activities)", self.menu)
        header_action.setEnabled(False)
        self.menu.addAction(header_action)

        status_action = QAction(tracking_state.status_message, self.menu)
        status_action.setEnabled(False)
        self.menu.addAction(status_action)

        self.menu.addSeparator()

        # Add activity breakdown
        for entry in summary:
            activity_name = entry.activity.value.replace('_', ' ').title()
            percentage = entry.percentage
            activity_action = QAction(f"{activity_name}: {percentage:.1f}%", self.menu)
            activity_action.setEnabled(False)
            self.menu.addAction(activity_action)

        self.menu.addSeparator()

        # Toggle action
        if tracking_state.can_toggle:
            is_active = self.is_tracking_active()
            toggle_text = "⏸️ Stop Tracking" if is_active else "▶️ Resume Tracking"
            toggle_action = QAction(toggle_text, self.menu)
            toggle_action.triggered.connect(self.toggle_tracking)
            self.menu.addAction(toggle_action)
        else:
            toggle_action = QAction("▶️ Resume Tracking (disabled)", self.menu)
            toggle_action.setEnabled(False)
            self.menu.addAction(toggle_action)

        self.menu.addSeparator()

        # Refresh action
        refresh_action = QAction("Refresh", self.menu)
        refresh_action.triggered.connect(self.refresh)
        self.menu.addAction(refresh_action)

        # View details action
        details_action = QAction("View Details", self.menu)
        details_action.triggered.connect(self.view_details)
        self.menu.addAction(details_action)

        self.menu.addSeparator()

        # Quit action
        quit_action = QAction("Quit", self.menu)
        quit_action.triggered.connect(self.quit_app)
        self.menu.addAction(quit_action)

    @Slot()
    def refresh(self):
        """Manually refresh the menu data."""
        logger.info("Manual refresh triggered")
        show_macos_notification(
            title="Zeit",
            subtitle="Refreshing...",
            message="Updating activity data"
        )
        self.update_menu()

    @Slot()
    def view_details(self):
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

                    show_macos_notification(
                        title="Zeit Activity Summary",
                        subtitle=f"{today} - {len(day_record.activities)} activities",
                        message=message
                    )
                else:
                    show_macos_notification(
                        title="Zeit",
                        subtitle="No Data",
                        message=f"No activities tracked for {today}"
                    )
        except Exception as e:
            logger.error(f"Error viewing details: {e}", exc_info=True)
            show_macos_notification(
                title="Zeit Error",
                subtitle="Failed to load details",
                message=str(e)
            )

    @Slot()
    def quit_app(self):
        """Quit the application."""
        logger.info("Quitting Zeit Menu Bar App")
        self.tray_icon.hide()
        self.app.quit()


def main():
    """Main entry point."""
    try:
        app = QApplication(sys.argv)
        app.setQuitOnLastWindowClosed(False)  # Keep running even with no windows

        menubar = ZeitMenuBar(app)

        sys.exit(app.exec())
    except Exception as e:
        logger.error(f"Failed to start menu bar app: {e}", exc_info=True)
        raise


if __name__ == "__main__":
    main()
