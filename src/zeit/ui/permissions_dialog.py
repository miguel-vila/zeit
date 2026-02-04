"""Permissions dialog for guiding users through macOS permission setup."""

import logging

from PySide6.QtCore import Qt, QTimer
from PySide6.QtGui import QCloseEvent, QFont
from PySide6.QtWidgets import (
    QDialog,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QSizePolicy,
    QVBoxLayout,
    QWidget,
)

from zeit.core.permissions import (
    PermissionStatus,
    all_permissions_granted,
    get_all_permission_statuses,
    open_system_settings,
)

logger = logging.getLogger(__name__)


class PermissionRow(QWidget):
    """A row displaying a single permission status with an action button."""

    def __init__(self, permission: PermissionStatus, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._permission = permission

        layout = QHBoxLayout()
        layout.setContentsMargins(0, 8, 0, 8)
        self.setLayout(layout)

        # Status indicator
        self._status_label = QLabel()
        self._status_label.setFixedWidth(24)
        self._status_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        layout.addWidget(self._status_label)

        # Permission info
        info_layout = QVBoxLayout()
        info_layout.setContentsMargins(0, 0, 0, 0)
        info_layout.setSpacing(2)

        name_label = QLabel(permission.name)
        name_font = QFont()
        name_font.setBold(True)
        name_label.setFont(name_font)
        info_layout.addWidget(name_label)

        desc_label = QLabel(permission.description)
        desc_label.setStyleSheet("color: gray;")
        desc_label.setWordWrap(True)
        info_layout.addWidget(desc_label)

        info_widget = QWidget()
        info_widget.setLayout(info_layout)
        info_widget.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Preferred)
        layout.addWidget(info_widget)

        # Action button
        self._action_button = QPushButton("Open Settings")
        self._action_button.setFixedWidth(120)
        self._action_button.clicked.connect(self._on_action_clicked)
        layout.addWidget(self._action_button)

        self._update_display()

    def update_status(self, granted: bool) -> None:
        """Update the permission status."""
        self._permission = PermissionStatus(
            name=self._permission.name,
            granted=granted,
            description=self._permission.description,
            settings_url=self._permission.settings_url,
        )
        self._update_display()

    def _update_display(self) -> None:
        """Update the visual display based on current status."""
        if self._permission.granted:
            self._status_label.setText("\u2713")  # Checkmark
            self._status_label.setStyleSheet("color: green; font-weight: bold; font-size: 16px;")
            self._action_button.setText("Granted")
            self._action_button.setEnabled(False)
        else:
            self._status_label.setText("\u2717")  # X mark
            self._status_label.setStyleSheet("color: red; font-weight: bold; font-size: 16px;")
            self._action_button.setText("Open Settings")
            self._action_button.setEnabled(True)

    def _on_action_clicked(self) -> None:
        """Handle the action button click."""
        open_system_settings(self._permission.settings_url)


class PermissionsDialog(QDialog):
    """
    Dialog for checking and guiding users through macOS permissions setup.

    Shows status of Screen Recording and Accessibility permissions,
    with buttons to open System Settings and auto-refresh to detect changes.
    """

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setWindowTitle("Permissions Required")
        self.setMinimumSize(500, 300)
        self.setWindowFlags(
            Qt.WindowType.Dialog
            | Qt.WindowType.WindowStaysOnTopHint
            | Qt.WindowType.CustomizeWindowHint
            | Qt.WindowType.WindowTitleHint
            | Qt.WindowType.WindowCloseButtonHint
        )

        self._permission_rows: list[PermissionRow] = []
        self._skipped = False

        self._setup_ui()
        self._setup_auto_refresh()

    def _setup_ui(self) -> None:
        """Set up the dialog UI."""
        main_layout = QVBoxLayout()
        main_layout.setContentsMargins(20, 20, 20, 20)
        main_layout.setSpacing(12)
        self.setLayout(main_layout)

        # Header
        header_label = QLabel("Permissions Required")
        header_font = QFont()
        header_font.setPointSize(18)
        header_font.setBold(True)
        header_label.setFont(header_font)
        main_layout.addWidget(header_label)

        # Explanation
        explanation = QLabel(
            "Zeit needs the following permissions to track your activities. "
            "Click 'Open Settings' to grant each permission, then return here."
        )
        explanation.setWordWrap(True)
        explanation.setStyleSheet("color: gray;")
        main_layout.addWidget(explanation)

        main_layout.addSpacing(10)

        # Permission rows
        for permission in get_all_permission_statuses():
            row = PermissionRow(permission, self)
            self._permission_rows.append(row)
            main_layout.addWidget(row)

        main_layout.addStretch()

        # Buttons
        buttons_layout = QHBoxLayout()

        self._check_button = QPushButton("Check Again")
        self._check_button.clicked.connect(self._refresh_permissions)
        buttons_layout.addWidget(self._check_button)

        buttons_layout.addStretch()

        self._skip_button = QPushButton("Skip for Now")
        self._skip_button.clicked.connect(self._on_skip)
        buttons_layout.addWidget(self._skip_button)

        self._continue_button = QPushButton("Continue")
        self._continue_button.setDefault(True)
        self._continue_button.clicked.connect(self.accept)
        buttons_layout.addWidget(self._continue_button)

        main_layout.addLayout(buttons_layout)

        # Initial state
        self._update_continue_button()

    def _setup_auto_refresh(self) -> None:
        """Set up a timer to auto-refresh permission status."""
        self._refresh_timer = QTimer(self)
        self._refresh_timer.timeout.connect(self._refresh_permissions)
        self._refresh_timer.start(2000)  # Check every 2 seconds

    def _refresh_permissions(self) -> None:
        """Refresh the permission statuses."""
        statuses = get_all_permission_statuses()
        for row, status in zip(self._permission_rows, statuses, strict=True):
            row.update_status(status.granted)
        self._update_continue_button()

    def _update_continue_button(self) -> None:
        """Enable/disable the Continue button based on permission status."""
        all_granted = all_permissions_granted()
        self._continue_button.setEnabled(all_granted)

    def _on_skip(self) -> None:
        """Handle the Skip button click."""
        self._skipped = True
        self.reject()

    def was_skipped(self) -> bool:
        """Return True if the user clicked Skip for Now."""
        return self._skipped

    def closeEvent(self, event: QCloseEvent) -> None:
        """Stop the timer when the dialog is closed."""
        self._refresh_timer.stop()
        super().closeEvent(event)


def show_permissions_dialog_if_needed(parent: QWidget | None = None) -> bool:
    """
    Show the permissions dialog if any permissions are missing.

    Args:
        parent: Optional parent widget for the dialog

    Returns:
        True if all permissions are granted (or were granted during the dialog),
        False if the user skipped or closed the dialog without granting permissions.
    """
    if all_permissions_granted():
        logger.debug("All permissions already granted")
        return True

    logger.info("Some permissions missing, showing dialog")
    dialog = PermissionsDialog(parent)
    result = dialog.exec()

    if result == QDialog.DialogCode.Accepted:
        logger.info("Permissions dialog completed - all permissions granted")
        return True

    if dialog.was_skipped():
        logger.warning("User skipped permissions dialog - some features may not work")
    else:
        logger.info("Permissions dialog closed without granting all permissions")

    return False
