"""
First-run setup dialog for Zeit.

Shows a welcome message and handles installation of CLI and LaunchAgents.
"""

import logging
from typing import TYPE_CHECKING

from PySide6.QtCore import QThread, Signal, Slot
from PySide6.QtGui import QCloseEvent, QFont
from PySide6.QtWidgets import (
    QDialog,
    QHBoxLayout,
    QLabel,
    QProgressBar,
    QPushButton,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

if TYPE_CHECKING:
    from zeit.core.installer import SetupResult

logger = logging.getLogger(__name__)


class SetupWorker(QThread):
    """Worker thread for running setup in the background."""

    finished = Signal(object)  # SetupResult
    progress = Signal(str)  # Progress message

    def run(self) -> None:
        """Execute the setup process."""
        from zeit.core.installer import run_full_setup

        self.progress.emit("Installing CLI binary...")
        result = run_full_setup(skip_menubar_service=True)
        self.finished.emit(result)


class SetupDialog(QDialog):
    """
    First-run setup dialog.

    Shows welcome message, explains installation, and handles setup process.
    """

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setWindowTitle("Welcome to Zeit")
        self.setMinimumSize(500, 400)
        self.setModal(True)

        self._worker: SetupWorker | None = None

        self._setup_ui()

    def _setup_ui(self) -> None:
        """Set up the dialog UI."""
        layout = QVBoxLayout()
        self.setLayout(layout)

        # Header
        header_label = QLabel("Welcome to Zeit")
        header_font = QFont()
        header_font.setPointSize(20)
        header_font.setBold(True)
        header_label.setFont(header_font)
        layout.addWidget(header_label)

        subtitle_label = QLabel("Activity Tracking for macOS")
        subtitle_font = QFont()
        subtitle_font.setPointSize(14)
        subtitle_label.setFont(subtitle_font)
        layout.addWidget(subtitle_label)

        layout.addSpacing(20)

        # Description
        desc_text = """
Zeit tracks your computer activity throughout the day, helping you understand
how you spend your time.

<b>What will be installed:</b>
<ul>
<li><b>CLI Tool</b> (~/.local/bin/zeit) - Command-line interface for viewing
and managing your activity data</li>
<li><b>Background Tracker</b> - LaunchAgent that captures screenshots every
minute during work hours</li>
</ul>

<b>Permissions required:</b>
<ul>
<li>Screen Recording - to capture screenshots</li>
<li>Accessibility - to detect the active window</li>
</ul>

<b>Note:</b> Your data stays local. Zeit uses Ollama for AI processing,
running entirely on your machine.
"""
        desc_label = QLabel(desc_text)
        desc_label.setWordWrap(True)
        desc_label.setTextFormat(desc_label.textFormat().RichText)
        layout.addWidget(desc_label)

        layout.addStretch()

        # Progress section (hidden initially)
        self._progress_container = QWidget()
        progress_layout = QVBoxLayout()
        progress_layout.setContentsMargins(0, 0, 0, 0)
        self._progress_container.setLayout(progress_layout)

        self._progress_bar = QProgressBar()
        self._progress_bar.setRange(0, 0)  # Indeterminate
        progress_layout.addWidget(self._progress_bar)

        self._progress_label = QLabel("Installing...")
        progress_layout.addWidget(self._progress_label)

        self._progress_container.hide()
        layout.addWidget(self._progress_container)

        # Result section (hidden initially)
        self._result_container = QWidget()
        result_layout = QVBoxLayout()
        result_layout.setContentsMargins(0, 0, 0, 0)
        self._result_container.setLayout(result_layout)

        self._result_label = QLabel()
        result_font = QFont()
        result_font.setBold(True)
        self._result_label.setFont(result_font)
        result_layout.addWidget(self._result_label)

        self._result_details = QTextEdit()
        self._result_details.setReadOnly(True)
        self._result_details.setMaximumHeight(100)
        result_layout.addWidget(self._result_details)

        self._result_container.hide()
        layout.addWidget(self._result_container)

        # Buttons
        button_layout = QHBoxLayout()

        self._skip_button = QPushButton("Skip Setup")
        self._skip_button.clicked.connect(self._on_skip)
        button_layout.addWidget(self._skip_button)

        button_layout.addStretch()

        self._install_button = QPushButton("Install")
        self._install_button.setDefault(True)
        self._install_button.clicked.connect(self._on_install)
        button_layout.addWidget(self._install_button)

        self._close_button = QPushButton("Close")
        self._close_button.clicked.connect(self.accept)
        self._close_button.hide()
        button_layout.addWidget(self._close_button)

        layout.addLayout(button_layout)

    @Slot()
    def _on_skip(self) -> None:
        """Handle skip button click."""
        logger.info("User skipped first-run setup")
        self.reject()

    @Slot()
    def _on_install(self) -> None:
        """Handle install button click."""
        logger.info("Starting first-run setup")

        # Hide buttons and show progress
        self._skip_button.setEnabled(False)
        self._install_button.setEnabled(False)
        self._progress_container.show()

        # Start worker thread
        self._worker = SetupWorker()
        self._worker.progress.connect(self._on_progress)
        self._worker.finished.connect(self._on_finished)
        self._worker.start()

    @Slot(str)
    def _on_progress(self, message: str) -> None:
        """Update progress display."""
        self._progress_label.setText(message)

    @Slot(object)
    def _on_finished(self, result: "SetupResult") -> None:
        """Handle setup completion."""
        self._progress_container.hide()
        self._result_container.show()

        if result.success:
            self._result_label.setText("Setup completed successfully!")
            self._result_label.setStyleSheet("color: green;")

            details = "Installed:\n"
            details += "  - CLI: ~/.local/bin/zeit\n"
            details += "  - Tracker service: co.invariante.zeit\n"
            details += "\nAdd ~/.local/bin to your PATH to use 'zeit' from terminal."
            self._result_details.setText(details)

            logger.info("First-run setup completed successfully")
        else:
            self._result_label.setText("Setup failed")
            self._result_label.setStyleSheet("color: red;")
            self._result_details.setText(f"Error: {result.error}")

            logger.error(f"First-run setup failed: {result.error}")

        # Show close button, hide install/skip
        self._skip_button.hide()
        self._install_button.hide()
        self._close_button.show()

    def closeEvent(self, event: QCloseEvent) -> None:
        """Handle dialog close."""
        if self._worker and self._worker.isRunning():
            # Don't allow closing during installation
            event.ignore()
        else:
            super().closeEvent(event)
