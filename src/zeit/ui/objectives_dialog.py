from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QFont
from PySide6.QtWidgets import (
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from zeit.core.utils import today_str
from zeit.data.db import DatabaseManager


class ObjectivesDialog(QWidget):
    """Dialog for setting day objectives."""

    objectives_saved = Signal()

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setWindowTitle("Set Day Objectives")
        self.setMinimumSize(450, 250)
        self.setWindowFlags(Qt.WindowType.Window | Qt.WindowType.WindowStaysOnTopHint)

        self._main_layout = QVBoxLayout()
        self.setLayout(self._main_layout)

        # Header
        header_label = QLabel("Set Your Day Objectives")
        header_font = QFont()
        header_font.setPointSize(16)
        header_font.setBold(True)
        header_label.setFont(header_font)
        self._main_layout.addWidget(header_label)

        self.date_label = QLabel()
        self._main_layout.addWidget(self.date_label)

        self._main_layout.addSpacing(10)

        # Main objective
        main_label = QLabel("Main Objective:")
        main_font = QFont()
        main_font.setBold(True)
        main_label.setFont(main_font)
        self._main_layout.addWidget(main_label)

        self.main_objective_input = QLineEdit()
        self.main_objective_input.setPlaceholderText(
            "e.g., Complete the API integration for project X"
        )
        self._main_layout.addWidget(self.main_objective_input)

        self._main_layout.addSpacing(10)

        # Secondary objectives
        secondary_label = QLabel("Secondary Objectives (optional):")
        secondary_label.setFont(main_font)
        self._main_layout.addWidget(secondary_label)

        self.secondary_1_input = QLineEdit()
        self.secondary_1_input.setPlaceholderText("e.g., Review pull requests")
        self._main_layout.addWidget(self.secondary_1_input)

        self.secondary_2_input = QLineEdit()
        self.secondary_2_input.setPlaceholderText("e.g., Write documentation")
        self._main_layout.addWidget(self.secondary_2_input)

        self._main_layout.addStretch()

        # Buttons
        buttons_layout = QHBoxLayout()

        cancel_button = QPushButton("Cancel")
        cancel_button.clicked.connect(self.close)
        buttons_layout.addWidget(cancel_button)

        save_button = QPushButton("Save")
        save_button.clicked.connect(self._save_objectives)
        save_button.setDefault(True)
        buttons_layout.addWidget(save_button)

        self._main_layout.addLayout(buttons_layout)

    def load_objectives_for_today(self) -> None:
        """Load existing objectives for today if they exist."""
        today = today_str()
        self.date_label.setText(f"Date: {today}")

        with DatabaseManager() as db:
            objectives = db.get_day_objectives(today)

        if objectives:
            self.main_objective_input.setText(objectives.main_objective)
            if len(objectives.secondary_objectives) > 0:
                self.secondary_1_input.setText(objectives.secondary_objectives[0])
            if len(objectives.secondary_objectives) > 1:
                self.secondary_2_input.setText(objectives.secondary_objectives[1])
        else:
            self.main_objective_input.clear()
            self.secondary_1_input.clear()
            self.secondary_2_input.clear()

    def _save_objectives(self) -> None:
        """Save objectives to the database."""
        main = self.main_objective_input.text().strip()
        if not main:
            return  # Main objective is required

        secondary: list[str] = []
        s1 = self.secondary_1_input.text().strip()
        s2 = self.secondary_2_input.text().strip()
        if s1:
            secondary.append(s1)
        if s2:
            secondary.append(s2)

        today = today_str()
        with DatabaseManager() as db:
            db.save_day_objectives(today, main, secondary)

        self.objectives_saved.emit()
        self.close()
