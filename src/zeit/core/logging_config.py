"""Centralized logging configuration for Zeit application.

Provides consistent logging setup across all entry points (tracker, menubar, CLI).
"""

import logging
from pathlib import Path
from typing import Optional

DEFAULT_LOG_DIR = "logs"
DEFAULT_LOG_FORMAT = "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
DEFAULT_DATE_FORMAT = "%Y-%m-%d %H:%M:%S"


def setup_logging(
    log_file: str = "zeit.log",
    log_dir: str = DEFAULT_LOG_DIR,
    file_level: int = logging.DEBUG,
    console_level: int = logging.INFO,
    log_format: Optional[str] = None,
) -> logging.Logger:
    """Configure logging to file and console.

    Args:
        log_file: Name of the log file (default: "zeit.log")
        log_dir: Directory for log files (default: "logs")
        file_level: Logging level for file handler (default: DEBUG)
        console_level: Logging level for console handler (default: INFO)
        log_format: Custom log format (default: standard format with timestamp)

    Returns:
        Logger instance for the calling module
    """
    # Ensure log directory exists
    log_path = Path(log_dir)
    log_path.mkdir(parents=True, exist_ok=True)

    # Use default format if not specified
    if log_format is None:
        log_format = DEFAULT_LOG_FORMAT

    # Create formatter
    formatter = logging.Formatter(log_format, datefmt=DEFAULT_DATE_FORMAT)

    # File handler
    file_handler = logging.FileHandler(log_path / log_file)
    file_handler.setLevel(file_level)
    file_handler.setFormatter(formatter)

    # Console handler
    console_handler = logging.StreamHandler()
    console_handler.setLevel(console_level)
    console_handler.setFormatter(formatter)

    # Configure root logger
    root_logger = logging.getLogger()
    root_logger.setLevel(logging.DEBUG)  # Allow all messages, handlers filter

    # Remove existing handlers to avoid duplicates on repeated calls
    root_logger.handlers.clear()

    root_logger.addHandler(file_handler)
    root_logger.addHandler(console_handler)

    return logging.getLogger(__name__)
