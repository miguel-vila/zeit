"""Idle detection module for macOS using ioreg."""

import subprocess
import logging
from typing import Optional

logger = logging.getLogger(__name__)

# Default idle threshold in seconds (5 minutes)
DEFAULT_IDLE_THRESHOLD = 300


def get_idle_time_seconds() -> Optional[float]:
    """
    Get the system idle time in seconds using macOS ioreg.

    Uses HIDIdleTime from IOHIDSystem to determine time since last keyboard/mouse input.

    Returns:
        Idle time in seconds, or None if unable to determine
    """
    try:
        # Query IOHIDSystem for HIDIdleTime
        output = subprocess.check_output(
            ['ioreg', '-c', 'IOHIDSystem'],
            text=True,
            timeout=5
        )

        # Parse the output to find HIDIdleTime
        for line in output.split('\n'):
            if 'HIDIdleTime' in line:
                # Format: "HIDIdleTime" = 12345678900
                # Value is in nanoseconds
                parts = line.split('=')
                if len(parts) >= 2:
                    idle_ns = int(parts[1].strip())
                    idle_seconds = idle_ns / 1_000_000_000
                    logger.debug(f"System idle time: {idle_seconds:.1f} seconds")
                    return idle_seconds

        logger.warning("HIDIdleTime not found in ioreg output")
        return None

    except subprocess.TimeoutExpired:
        logger.error("ioreg command timed out")
        return None
    except subprocess.CalledProcessError as e:
        logger.error(f"ioreg command failed: {e}")
        return None
    except ValueError as e:
        logger.error(f"Failed to parse HIDIdleTime value: {e}")
        return None
    except Exception as e:
        logger.error(f"Unexpected error getting idle time: {e}", exc_info=True)
        return None


def is_system_idle(threshold_seconds: int = DEFAULT_IDLE_THRESHOLD) -> bool:
    """
    Check if the system is currently idle.

    Args:
        threshold_seconds: Number of seconds of inactivity to consider as idle

    Returns:
        True if system has been idle for longer than threshold, False otherwise
    """
    idle_time = get_idle_time_seconds()

    if idle_time is None:
        # Unable to determine idle time, assume not idle
        logger.warning("Unable to determine idle time, assuming system is active")
        return False

    is_idle = idle_time >= threshold_seconds

    if is_idle:
        logger.info(f"System is idle: {idle_time:.1f}s (threshold: {threshold_seconds}s)")
    else:
        logger.debug(f"System is active: idle for {idle_time:.1f}s")

    return is_idle
