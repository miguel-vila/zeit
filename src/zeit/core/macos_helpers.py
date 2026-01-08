"""macOS-specific helpers for AppleScript execution."""

import subprocess


class AppleScriptError(Exception):
    """Raised when AppleScript execution fails."""


def run_applescript(script: str, timeout: int = 5) -> str:
    """Execute AppleScript and return the output.

    Args:
        script: AppleScript code to execute
        timeout: Timeout in seconds (default: 5)

    Returns:
        The stdout output from the script

    Raises:
        AppleScriptError: If the script fails or times out
    """
    try:
        result = subprocess.run(
            ["osascript", "-e", script], capture_output=True, text=True, timeout=timeout
        )

        if result.returncode != 0:
            raise AppleScriptError(f"AppleScript failed: {result.stderr.strip()}")

        return result.stdout.strip()

    except subprocess.TimeoutExpired as e:
        raise AppleScriptError("AppleScript timed out") from e


def run_applescript_safe(script: str, timeout: int = 5) -> str | None:
    """Execute AppleScript, returning None on failure instead of raising.

    Args:
        script: AppleScript code to execute
        timeout: Timeout in seconds (default: 5)

    Returns:
        The stdout output from the script, or None if execution failed
    """
    try:
        return run_applescript(script, timeout)
    except AppleScriptError:
        return None
