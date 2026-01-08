from PySide6.QtCore import Qt
from PySide6.QtGui import QFont
from PySide6.QtWidgets import QHBoxLayout, QLabel, QProgressBar, QPushButton, QVBoxLayout, QWidget

from zeit.data.db import DayRecord
from zeit.processing.activity_summarization import ActivityWithPercentage, compute_summary

PROGRESS_BAR_STYLE = """
    QProgressBar {{
        border: 1px solid #cccccc;
        border-radius: 4px;
        background-color: #f0f0f0;
    }}
    QProgressBar::chunk {{
        background-color: {color};
        border-radius: 3px;
    }}
"""

WORK_ACTIVITY_COLOR = "#4CAF50"
PERSONAL_ACTIVITY_COLOR = "#2196F3"


class DetailsWindow(QWidget):
    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setWindowTitle("Zeit Activity Details")
        self.setMinimumSize(400, 300)
        self.setWindowFlags(Qt.WindowType.Window | Qt.WindowType.WindowStaysOnTopHint)

        self._main_layout = QVBoxLayout()
        self.setLayout(self._main_layout)

        self.header_label = QLabel()
        header_font = QFont()
        header_font.setPointSize(16)
        header_font.setBold(True)
        self.header_label.setFont(header_font)
        self._main_layout.addWidget(self.header_label)

        self.date_label = QLabel()
        self._main_layout.addWidget(self.date_label)

        self.activities_layout = QVBoxLayout()
        self._main_layout.addLayout(self.activities_layout)

        self._main_layout.addStretch()

        close_button = QPushButton("Close")
        close_button.clicked.connect(self.close)
        self._main_layout.addWidget(close_button)

    def _create_progress_bar(self, percentage: float, is_work: bool) -> QProgressBar:
        progress_bar = QProgressBar()
        progress_bar.setMaximum(100)
        progress_bar.setValue(int(percentage))
        progress_bar.setTextVisible(False)
        progress_bar.setMaximumHeight(8)
        color = WORK_ACTIVITY_COLOR if is_work else PERSONAL_ACTIVITY_COLOR
        progress_bar.setStyleSheet(PROGRESS_BAR_STYLE.format(color=color))
        return progress_bar

    def _create_activity_widget(self, entry: ActivityWithPercentage) -> QWidget:
        activity_name = entry.activity.value.replace("_", " ").title()
        percentage = entry.percentage

        activity_widget = QWidget()
        activity_layout = QVBoxLayout()
        activity_widget.setLayout(activity_layout)

        label_layout = QHBoxLayout()
        name_label = QLabel(activity_name)
        name_font = QFont()
        name_font.setPointSize(12)
        name_label.setFont(name_font)
        label_layout.addWidget(name_label)

        pct_label = QLabel(f"{percentage:.1f}%")
        pct_font = QFont()
        pct_font.setPointSize(12)
        pct_font.setBold(True)
        pct_label.setFont(pct_font)
        label_layout.addWidget(pct_label)

        activity_layout.addLayout(label_layout)
        activity_layout.addWidget(
            self._create_progress_bar(percentage, entry.activity.is_work_activity())
        )
        activity_layout.setSpacing(4)
        activity_layout.setContentsMargins(0, 4, 0, 8)

        return activity_widget

    def update_data(self, day_record: DayRecord, date_str: str) -> None:
        while self.activities_layout.count():
            item = self.activities_layout.takeAt(0)
            if item.widget():
                item.widget().deleteLater()

        total_count = len(day_record.activities)
        self.header_label.setText("Activity Summary")
        self.date_label.setText(f"{date_str} • {total_count} activities tracked")

        summary = compute_summary(day_record.activities)
        for entry in summary:
            self.activities_layout.addWidget(self._create_activity_widget(entry))
