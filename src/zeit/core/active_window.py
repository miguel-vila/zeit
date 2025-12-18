"""Native macOS active window detection.

Uses AppleScript and Quartz to detect which monitor contains the active window.
"""

import subprocess
import logging
from typing import NamedTuple, List
import mss

logger = logging.getLogger(__name__)


class WindowBounds(NamedTuple):
    """Window bounds in screen coordinates."""
    x: int
    y: int
    width: int
    height: int


class DisplayBounds(NamedTuple):
    """Display bounds from Quartz."""
    x: float
    y: float
    width: float
    height: float


def get_frontmost_window_bounds() -> WindowBounds:
    """Get the bounds of the frontmost window using AppleScript.
    
    Returns:
        WindowBounds with x, y, width, height
        
    Raises:
        RuntimeError: If unable to get window bounds
    """
    applescript = '''
tell application "System Events"
    set frontApp to first application process whose frontmost is true
    tell frontApp
        if (count of windows) > 0 then
            set win to window 1
            set {x, y} to position of win
            set {w, h} to size of win
            return (x as text) & "," & (y as text) & "," & (w as text) & "," & (h as text)
        else
            error "No windows found for frontmost application"
        end if
    end tell
end tell
'''
    try:
        result = subprocess.run(
            ['osascript', '-e', applescript],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        if result.returncode != 0:
            raise RuntimeError(f"AppleScript failed: {result.stderr.strip()}")
        
        output = result.stdout.strip()
        if not output:
            raise RuntimeError("AppleScript returned empty output")
        
        parts = output.split(',')
        if len(parts) != 4:
            raise RuntimeError(f"Unexpected AppleScript output format: {output}")
        
        x, y, w, h = map(int, parts)
        logger.debug(f"Frontmost window bounds: x={x}, y={y}, width={w}, height={h}")
        return WindowBounds(x, y, w, h)
        
    except subprocess.TimeoutExpired:
        raise RuntimeError("AppleScript timed out")
    except ValueError as e:
        raise RuntimeError(f"Failed to parse window bounds: {e}")


def get_mss_monitors() -> List[DisplayBounds]:
    """Get monitor bounds from mss (matching the order used in MultiScreenCapture).
    
    Returns:
        List of DisplayBounds for each monitor (excluding virtual combined screen)
    """
    with mss.mss() as sct:
        monitors: List[DisplayBounds] = []
        # Skip index 0 (virtual combined screen), same as MultiScreenCapture
        for monitor in sct.monitors[1:]:
            monitors.append(DisplayBounds(
                x=monitor['left'],
                y=monitor['top'],
                width=monitor['width'],
                height=monitor['height']
            ))
        return monitors


def _point_in_display(x: int, y: int, display: DisplayBounds) -> bool:
    """Check if a point is within a display's bounds."""
    return (
        display.x <= x < display.x + display.width and
        display.y <= y < display.y + display.height
    )


def _find_display_for_window(window: WindowBounds, displays: List[DisplayBounds]) -> int:
    """Find which display contains the window's top-left corner.
    
    Returns:
        0-based index of the display containing the window
        
    Raises:
        RuntimeError: If window is not on any display
    """
    # Use window's top-left corner as the reference point
    for idx, display in enumerate(displays):
        if _point_in_display(window.x, window.y, display):
            return idx
    
    # Try window center as fallback
    center_x = window.x + window.width // 2
    center_y = window.y + window.height // 2
    for idx, display in enumerate(displays):
        if _point_in_display(center_x, center_y, display):
            return idx
    
    raise RuntimeError(
        f"Window at ({window.x}, {window.y}) not found on any display. "
        f"Displays: {displays}"
    )


def get_active_screen_number() -> int:
    """Get the screen number (1-based) containing the active window.
    
    This uses mss monitor ordering (same as MultiScreenCapture) so the
    returned number matches the screen indices used for screenshots.
    
    Returns:
        Screen number (1, 2, 3, ...) containing the active window
        
    Raises:
        RuntimeError: If unable to detect active screen
    """
    # Get frontmost window bounds
    window = get_frontmost_window_bounds()
    logger.info(f"Active window bounds: {window}")
    
    # Get mss monitors (this is what MultiScreenCapture uses)
    mss_monitors = get_mss_monitors()
    logger.debug(f"MSS monitors: {mss_monitors}")
    
    if len(mss_monitors) == 0:
        raise RuntimeError("No monitors found")
    
    if len(mss_monitors) == 1:
        # Only one monitor, no need to detect
        return 1
    
    # Find which monitor contains the window
    monitor_idx = _find_display_for_window(window, mss_monitors)
    screen_number = monitor_idx + 1  # Convert to 1-based
    
    logger.info(f"Active window is on screen {screen_number}")
    return screen_number
