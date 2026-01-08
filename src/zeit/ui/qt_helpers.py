#!/usr/bin/env python3
"""Qt helper utilities for PySide6 implementation."""

import logging
from typing import Optional

from PySide6.QtCore import Qt
from PySide6.QtGui import QFont, QIcon, QPainter, QPixmap

from zeit.core.macos_helpers import AppleScriptError, run_applescript

logger = logging.getLogger(__name__)


def emoji_to_qicon(emoji: str, size: int = 22) -> QIcon:
    """
    Convert an emoji string to a QIcon for use in system tray.

    Args:
        emoji: Emoji character(s) to render
        size: Size in pixels (default 22 for macOS menu bar)

    Returns:
        QIcon containing the rendered emoji
    """
    # Create a pixmap to draw on
    pixmap = QPixmap(size, size)
    pixmap.fill(Qt.GlobalColor.transparent)

    # Draw the emoji
    painter = QPainter(pixmap)
    painter.setRenderHint(QPainter.RenderHint.Antialiasing)
    painter.setRenderHint(QPainter.RenderHint.TextAntialiasing)

    # Use a font that supports emoji
    font = QFont("Apple Color Emoji", size - 4)  # Slightly smaller than pixmap
    painter.setFont(font)

    # Draw centered
    painter.drawText(pixmap.rect(), Qt.AlignmentFlag.AlignCenter, emoji)
    painter.end()

    return QIcon(pixmap)


def show_macos_notification(title: str, subtitle: str = "", message: str = "") -> bool:
    """
    Show a native macOS notification using osascript.

    Args:
        title: Notification title
        subtitle: Notification subtitle (optional)
        message: Notification message body

    Returns:
        True if notification was sent successfully, False otherwise
    """
    try:
        if subtitle:
            script = (
                f'''display notification "{message}" with title "{title}" subtitle "{subtitle}"'''
            )
        else:
            script = f'''display notification "{message}" with title "{title}"'''

        run_applescript(script)
        return True

    except AppleScriptError as e:
        logger.error(f"Notification failed: {e}")
        return False
    except Exception as e:
        logger.error(f"Error showing notification: {e}", exc_info=True)
        return False


def text_to_qicon(text: str, size: int = 22, font_size: Optional[int] = None) -> QIcon:
    """
    Convert text (including percentage symbols) to a QIcon for system tray.

    Args:
        text: Text to render
        size: Icon size in pixels
        font_size: Font size (defaults to size - 4)

    Returns:
        QIcon containing the rendered text
    """
    if font_size is None:
        font_size = size - 4

    # Create a pixmap
    pixmap = QPixmap(size * len(text), size)
    pixmap.fill(Qt.GlobalColor.transparent)

    # Draw the text
    painter = QPainter(pixmap)
    painter.setRenderHint(QPainter.RenderHint.Antialiasing)
    painter.setRenderHint(QPainter.RenderHint.TextAntialiasing)

    # Use system font for text
    font = QFont(".AppleSystemUIFont", font_size)
    painter.setFont(font)

    # Draw text
    painter.drawText(pixmap.rect(), Qt.AlignmentFlag.AlignCenter, text)
    painter.end()

    return QIcon(pixmap)
