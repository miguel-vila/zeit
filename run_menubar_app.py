#!/usr/bin/env python3
"""Entry point for Zeit Menu Bar App."""

import sys
from pathlib import Path

# Add src directory to Python path for development
src_path = Path(__file__).parent / "src"
if str(src_path) not in sys.path:
    sys.path.insert(0, str(src_path))

from zeit.ui.menubar import main  # noqa: E402

if __name__ == "__main__":
    main()
