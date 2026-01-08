import logging
import os
import sys
from datetime import datetime
from time import sleep

import opik
from dotenv import load_dotenv
from ollama import Client

from zeit.core.activity_id import ActivityIdentifier
from zeit.core.config import get_config
from zeit.core.idle_detection import DEFAULT_IDLE_THRESHOLD, is_system_idle
from zeit.core.logging_config import setup_logging
from zeit.data.db import ActivityEntry, DatabaseManager


def main() -> int | None:
    load_dotenv()  # Load environment variables from .env file if present
    setup_logging(log_file="zeit.log")
    logger = logging.getLogger(__name__)
    if os.getenv("OPIK_URL"):
        logger.info(f"Running with local Opik instance at {os.getenv('OPIK_URL')}")
        opik.configure(url=os.getenv("OPIK_URL"), use_local=True)
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

        # Get idle threshold from environment variable or use default
        idle_threshold = int(os.getenv("IDLE_THRESHOLD_SECONDS", DEFAULT_IDLE_THRESHOLD))
        logger.debug(f"Using idle threshold: {idle_threshold} seconds")

        # Check if system is idle
        if is_system_idle(idle_threshold):
            logger.info("System is idle, recording idle state instead of taking screenshot")

            # Create idle entry
            idle_entry = ActivityEntry.idle(datetime.now())

            # Save to database
            with DatabaseManager() as db:
                success = db.insert_activity(idle_entry)

                if not success:
                    logger.error("Failed to save idle state to database")
                    return 1

                logger.info("Idle state successfully saved to database")

            return 0

        # System is active - proceed with screenshot and identification
        logger.debug("Initializing Ollama client")
        client = Client()
        config = get_config()
        identifier = ActivityIdentifier(ollama_client=client, models_config=config.models)

        # Take screenshot of all screens and identify activity
        activities_response = identifier.take_screenshot_and_describe()

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
