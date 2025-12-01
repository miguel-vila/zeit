from ollama import Client
from time import sleep
import sys
import logging
from pathlib import Path
from activity_id import ActivityIdentifier
from db import DatabaseManager, ActivityEntry

def setup_logging():
    """Configure logging to file and console."""
    log_dir = "logs"
    Path(log_dir).mkdir(parents=True, exist_ok=True)
    log_file = Path(log_dir) / "zeit.log"

    # Create formatter
    formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )

    # File handler (DEBUG level)
    file_handler = logging.FileHandler(log_file)
    file_handler.setLevel(logging.DEBUG)
    file_handler.setFormatter(formatter)

    # Console handler (INFO level)
    console_handler = logging.StreamHandler()
    console_handler.setLevel(logging.INFO)
    console_handler.setFormatter(formatter)

    # Configure root logger
    root_logger = logging.getLogger()
    root_logger.setLevel(logging.DEBUG)
    root_logger.addHandler(file_handler)
    root_logger.addHandler(console_handler)

    return logging.getLogger(__name__)

def main():
    logger = setup_logging()
    logger.info("=" * 60)
    logger.info("Starting zeit activity tracker")

    try:
        # user may pass a second delay argument to wait before taking screenshot
        delay = 0
        if len(sys.argv) > 1:
            try:
                delay = int(sys.argv[1])
            except ValueError:
                logger.error(f"Invalid delay argument: {sys.argv[1]}")
                return 1

        if delay > 0:
            logger.info(f"Waiting for {delay} seconds before taking screenshot...")
            sleep(delay)

        # Initialize Ollama client and activity identifier
        logger.debug("Initializing Ollama client")
        client = Client()
        identifier = ActivityIdentifier(ollama_client=client)

        # Take screenshot and identify activity
        activities_response = identifier.take_screenshot_and_describe(1)

        if activities_response is None:
            logger.error("Failed to identify activity")
            return 1

        # Log results
        logger.info("=" * 60)
        logger.info(f"Activity: {activities_response.main_activity.value}")
        logger.info(f"Reasoning: {activities_response.reasoning}")
        logger.info("=" * 60)

        # Save to database
        logger.debug("Saving activity to database")
        with DatabaseManager() as db:
            activity_entry = ActivityEntry.from_response(activities_response)
            success = db.insert_activity(activity_entry)

            if not success:
                logger.error("Failed to save activity to database")
                return 1

            logger.info("Activity successfully saved to database")

        return 0

    except KeyboardInterrupt:
        logger.info("Interrupted by user")
        return 130
    except Exception as e:
        logger.error(f"Unexpected error in main: {e}", exc_info=True)
        return 1

if __name__ == "__main__":
    exit_code = main()
    sys.exit(exit_code)
