"""Permission detection for macOS Screen Recording and Accessibility."""

import ctypes
import ctypes.util
import logging
import subprocess
from dataclasses import dataclass

logger = logging.getLogger(__name__)


@dataclass
class PermissionStatus:
    """Status of a single permission."""

    name: str
    granted: bool
    description: str
    settings_url: str


# Deep links to System Settings privacy panes
SCREEN_RECORDING_SETTINGS_URL = (
    "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
)
ACCESSIBILITY_SETTINGS_URL = (
    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
)


def check_screen_recording_permission() -> bool:
    """
    Check if Screen Recording permission is granted.

    Uses CGPreflightScreenCaptureAccess() from CoreGraphics framework.
    This function returns True if access would be granted, False otherwise.
    It does not prompt the user for permission.
    """
    try:
        core_graphics_path = ctypes.util.find_library("CoreGraphics")
        if core_graphics_path is None:
            logger.warning("CoreGraphics framework not found")
            return False

        core_graphics = ctypes.cdll.LoadLibrary(core_graphics_path)
        preflight_func = core_graphics.CGPreflightScreenCaptureAccess
        preflight_func.restype = ctypes.c_bool

        return bool(preflight_func())
    except Exception as e:
        logger.warning(f"Failed to check screen recording permission: {e}")
        return False


def check_accessibility_permission() -> bool:
    """
    Check if Accessibility permission is granted.

    Uses AXIsProcessTrusted() from ApplicationServices framework.
    This function returns True if the app is trusted for accessibility,
    False otherwise. It does not prompt the user for permission.
    """
    try:
        app_services_path = ctypes.util.find_library("ApplicationServices")
        if app_services_path is None:
            logger.warning("ApplicationServices framework not found")
            return False

        app_services = ctypes.cdll.LoadLibrary(app_services_path)
        ax_is_trusted = app_services.AXIsProcessTrusted
        ax_is_trusted.restype = ctypes.c_bool

        return bool(ax_is_trusted())
    except Exception as e:
        logger.warning(f"Failed to check accessibility permission: {e}")
        return False


def get_all_permission_statuses() -> list[PermissionStatus]:
    """Get the status of all required permissions."""
    return [
        PermissionStatus(
            name="Screen Recording",
            granted=check_screen_recording_permission(),
            description="Required to capture screenshots for activity tracking",
            settings_url=SCREEN_RECORDING_SETTINGS_URL,
        ),
        PermissionStatus(
            name="Accessibility",
            granted=check_accessibility_permission(),
            description="Required to detect which window is currently active",
            settings_url=ACCESSIBILITY_SETTINGS_URL,
        ),
    ]


def all_permissions_granted() -> bool:
    """Check if all required permissions are granted."""
    return all(p.granted for p in get_all_permission_statuses())


def open_system_settings(url: str) -> bool:
    """
    Open System Settings to a specific privacy pane.

    Args:
        url: The x-apple.systempreferences URL to open

    Returns:
        True if the command succeeded, False otherwise
    """
    try:
        subprocess.run(["open", url], check=True)
        return True
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to open System Settings: {e}")
        return False
    except Exception as e:
        logger.error(f"Unexpected error opening System Settings: {e}")
        return False
