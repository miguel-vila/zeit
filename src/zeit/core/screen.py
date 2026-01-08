from datetime import datetime
import logging
from pathlib import Path
from typing import Dict
import mss
import mss.tools
import os

logger = logging.getLogger(__name__)


class MultiScreenCapture:
    """Context manager that captures all connected monitors.
    
    Skips monitor index 0 (mss's virtual combined screen) and captures
    all real monitors. Cleans up all screenshots on exit.
    """

    def __init__(self, now: datetime):
        self.now = now
        self.screenshot_paths: Dict[int, Path] = {}

    def __enter__(self) -> Dict[int, Path]:
        self.screenshot_paths = self._capture_all_monitors()
        return self.screenshot_paths

    def _capture_all_monitors(self) -> Dict[int, Path]:
        now_str = self.now.isoformat()
        os.makedirs("screenshots", exist_ok=True)
        paths: Dict[int, Path] = {}

        with mss.mss() as sct:
            # Skip index 0 (virtual combined screen), capture all real monitors
            real_monitors = sct.monitors[1:]
            logger.info(f"Capturing {len(real_monitors)} monitor(s)")

            for idx, monitor in enumerate(real_monitors, start=1):
                screenshot = sct.grab(monitor)
                file_name = f"screenshots/screenshot_{idx}_{now_str}.png"
                mss.tools.to_png(screenshot.rgb, screenshot.size, output=file_name)
                paths[idx] = Path(os.path.abspath(file_name))
                logger.debug(f"Captured monitor {idx}: {paths[idx]}")

        return paths

    def __exit__(self, exc_type, exc_value, traceback):
        for monitor_id, path in self.screenshot_paths.items():
            if path and os.path.exists(path):
                os.remove(path)
                logger.debug(f"Deleted screenshot {path}")
        logger.info(f"Cleaned up {len(self.screenshot_paths)} screenshot(s)")    
