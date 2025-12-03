from datetime import datetime
import logging
from pathlib import Path
import mss
import mss.tools
import os

logger = logging.getLogger(__name__)

class EphemeralScreenshot:
    
    def __init__(self, monitor_id: int, now: datetime):
        self.monitor_id = monitor_id
        self.now = now
    
    def __enter__(self) -> Path:
        self.screenshot_path = self._take_screenshot(self.monitor_id)
        return self.screenshot_path
    
    def _take_screenshot(self, monitor_id: int) -> Path:
        # Take screenshot
        now = self.now.isoformat()
        logger.info(f"Taking screenshot from monitor {monitor_id}")
        with mss.mss() as sct:
            if monitor_id >= len(sct.monitors):
                logger.error(
                    f"Invalid monitor ID {monitor_id}. Available monitors: {len(sct.monitors) - 1}"
                )
                raise ValueError(f"Invalid monitor ID {monitor_id}")
            screenshot = sct.grab(sct.monitors[monitor_id])

        file_name = f"screenshots/screenshot_{monitor_id}_{now}.png"
        os.makedirs("screenshots", exist_ok=True)
        mss.tools.to_png(screenshot.rgb, screenshot.size, output=file_name)
        return Path(os.path.abspath(file_name))
    
    def __exit__(self, exc_type, exc_value, traceback):
        if self.screenshot_path and os.path.exists(self.screenshot_path):
            os.remove(self.screenshot_path)
            logger.info(f"Deleted screenshot {self.screenshot_path}")    
