"""Configuration management for Zeit activity tracker."""

import logging
from datetime import datetime, time
from pathlib import Path
from typing import Any

import yaml
from pydantic import BaseModel, Field, field_validator

logger = logging.getLogger(__name__)

# Central data directory for all Zeit files
DATA_DIR = Path.home() / ".local" / "share" / "zeit"


class WorkHoursConfig(BaseModel):
    """Work hours configuration with validation."""

    work_start_hour: time = Field(description="Work start time (HH:MM format)")
    work_end_hour: time = Field(description="Work end time (HH:MM format)")

    @field_validator("work_start_hour", "work_end_hour", mode="before")
    @classmethod
    def parse_time_string(cls, v: Any) -> time:
        """Parse time string in HH:MM format to time object."""
        if isinstance(v, str):
            try:
                hour, minute = v.split(":")
                return time(int(hour), int(minute))
            except (ValueError, AttributeError) as e:
                raise ValueError(f"Invalid time format: {v}. Expected HH:MM") from e
        raise ValueError(f"Invalid time type: {type(v)}")

    def is_within_work_hours(self, check_time: datetime | None = None) -> bool:
        """
        Check if given time (or now) is within work hours.

        Args:
            check_time: Time to check, defaults to current time

        Returns:
            True if within work hours (Monday-Friday, between configured times)
        """
        if check_time is None:
            check_time = datetime.now()

        # Check weekday (0=Monday, 6=Sunday)
        if check_time.weekday() > 4:  # Saturday=5, Sunday=6
            logger.debug(f"Outside work hours: Weekend ({check_time.strftime('%A')})")
            return False

        # Check time of day
        current_time = check_time.time()
        if current_time < self.work_start_hour or current_time >= self.work_end_hour:
            logger.debug(
                f"Outside work hours: {current_time.strftime('%H:%M')} "
                f"not in {self.work_start_hour.strftime('%H:%M')}-"
                f"{self.work_end_hour.strftime('%H:%M')}"
            )
            return False

        return True

    def get_status_message(self, check_time: datetime | None = None) -> str:
        """
        Get human-readable status message about work hours.

        Returns:
            Message like "Outside work hours (Weekend)" or
            "Outside work hours (After 17:30)"
        """
        if check_time is None:
            check_time = datetime.now()

        if check_time.weekday() > 4:
            return f"Outside work hours ({check_time.strftime('%A')})"

        current_time = check_time.time()
        if current_time < self.work_start_hour:
            return f"Outside work hours (Before {self.work_start_hour.strftime('%H:%M')})"
        if current_time >= self.work_end_hour:
            return f"Outside work hours (After {self.work_end_hour.strftime('%H:%M')})"

        return "Within work hours"


class ModelsConfig(BaseModel):
    vision: str = Field(default="qwen3-vl:4b", description="Vision model for image analysis")
    text: str = Field(
        default="qwen3:8b", description="Text model for classification and summarization"
    )


class PathsConfig(BaseModel):
    """Configuration for application paths."""

    data_dir: Path = Field(default=DATA_DIR, description="Base data directory")
    stop_flag: Path = Field(default=DATA_DIR / ".zeit_stop", description="Path to stop flag file")
    db_path: Path = Field(default=DATA_DIR / "zeit.db", description="Path to SQLite database")

    @field_validator("data_dir", "stop_flag", "db_path", mode="before")
    @classmethod
    def expand_path(cls, v: Any) -> Path:
        """Expand ~ to user home directory."""
        if isinstance(v, str):
            return Path(v).expanduser()
        if isinstance(v, Path):
            return v.expanduser()
        raise ValueError(f"Invalid path type: {type(v)}")


class ZeitConfig(BaseModel):
    work_hours: WorkHoursConfig
    models: ModelsConfig = Field(default_factory=ModelsConfig)
    paths: PathsConfig = Field(default_factory=PathsConfig)


def _get_bundled_config_path() -> Path:
    """Get path to the bundled default config file."""
    return Path(__file__).parent / "conf.yml"


def _get_user_config_path() -> Path:
    """Get path to the user's config file in DATA_DIR."""
    return DATA_DIR / "conf.yml"


def _ensure_user_config() -> Path:
    """
    Ensure user config exists, copying from bundled default if needed.

    Returns:
        Path to the user config file
    """
    user_config = _get_user_config_path()
    bundled_config = _get_bundled_config_path()

    # Ensure data directory exists
    DATA_DIR.mkdir(parents=True, exist_ok=True)

    if not user_config.exists():
        if bundled_config.exists():
            # Copy bundled config to user location
            import shutil

            shutil.copy(bundled_config, user_config)
            logger.info(f"Copied default config to {user_config}")
        else:
            raise FileNotFoundError(
                f"No config found at {user_config} and no bundled default at {bundled_config}"
            )

    return user_config


def load_config(config_path: Path | None = None) -> ZeitConfig:
    """
    Load configuration from conf.yml.

    Args:
        config_path: Path to config file. If None, uses user config at
                     ~/.local/share/zeit/conf.yml (copying bundled default if needed)

    Returns:
        Validated ZeitConfig object

    Raises:
        FileNotFoundError: If config file doesn't exist
        ValueError: If config is invalid
    """
    if config_path is None:
        config_path = _ensure_user_config()

    if not config_path.exists():
        raise FileNotFoundError(f"Configuration file not found: {config_path}")

    logger.debug(f"Loading configuration from {config_path}")

    with open(config_path) as f:
        config_data = yaml.safe_load(f)

    return ZeitConfig(**config_data)


# Singleton pattern for config
_config_instance: ZeitConfig | None = None


def get_config() -> ZeitConfig:
    """Get or load the configuration singleton."""
    global _config_instance
    if _config_instance is None:
        _config_instance = load_config()
    return _config_instance


def is_within_work_hours(check_time: datetime | None = None) -> bool:
    """
    Convenience function to check if currently in work hours.

    Args:
        check_time: Time to check, defaults to current time

    Returns:
        True if within work hours
    """
    config = get_config()
    return config.work_hours.is_within_work_hours(check_time)
