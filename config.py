"""Configuration management for Zeit activity tracker."""

from datetime import time, datetime
from pathlib import Path
from typing import Optional
import yaml
from pydantic import BaseModel, Field, field_validator
import logging

logger = logging.getLogger(__name__)


class WorkHoursConfig(BaseModel):
    """Work hours configuration with validation."""

    work_start_hour: time = Field(description="Work start time (HH:MM format)")
    work_end_hour: time = Field(description="Work end time (HH:MM format)")

    @field_validator('work_start_hour', 'work_end_hour', mode='before')
    @classmethod
    def parse_time_string(cls, v):
        """Parse time string in HH:MM format to time object."""
        if isinstance(v, str):
            try:
                hour, minute = v.split(':')
                return time(int(hour), int(minute))
            except (ValueError, AttributeError) as e:
                raise ValueError(f"Invalid time format: {v}. Expected HH:MM") from e
        raise ValueError(f"Invalid time type: {type(v)}")

    def is_within_work_hours(self, check_time: Optional[datetime] = None) -> bool:
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

    def get_status_message(self, check_time: Optional[datetime] = None) -> str:
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
        elif current_time >= self.work_end_hour:
            return f"Outside work hours (After {self.work_end_hour.strftime('%H:%M')})"

        return "Within work hours"


class ZeitConfig(BaseModel):
    """Main Zeit configuration."""

    work_hours: WorkHoursConfig


def load_config(config_path: Optional[Path] = None) -> ZeitConfig:
    """
    Load configuration from conf.yml.

    Args:
        config_path: Path to config file, defaults to ./conf.yml

    Returns:
        Validated ZeitConfig object

    Raises:
        FileNotFoundError: If config file doesn't exist
        ValueError: If config is invalid
    """
    if config_path is None:
        config_path = Path(__file__).parent / "conf.yml"

    if not config_path.exists():
        raise FileNotFoundError(f"Configuration file not found: {config_path}")

    logger.debug(f"Loading configuration from {config_path}")

    with open(config_path, 'r') as f:
        config_data = yaml.safe_load(f)

    # Transform flat structure to nested if needed
    if 'work-start-hour' in config_data:
        config_data = {
            'work_hours': {
                'work_start_hour': config_data['work-start-hour'],
                'work_end_hour': config_data['work-end-hour']
            }
        }

    return ZeitConfig(**config_data)


# Singleton pattern for config
_config_instance: Optional[ZeitConfig] = None


def get_config() -> ZeitConfig:
    """Get or load the configuration singleton."""
    global _config_instance
    if _config_instance is None:
        _config_instance = load_config()
    return _config_instance


def is_within_work_hours(check_time: Optional[datetime] = None) -> bool:
    """
    Convenience function to check if currently in work hours.

    Args:
        check_time: Time to check, defaults to current time

    Returns:
        True if within work hours
    """
    config = get_config()
    return config.work_hours.is_within_work_hours(check_time)
