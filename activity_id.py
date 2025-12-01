from enum import Enum
from pathlib import Path
import mss
import mss.tools
import os
from time import time
import base64
from pydantic import BaseModel, Field
from ollama import Client
from datetime import datetime
import logging
from typing import Optional

class Activity(str, Enum):
    # Personal activities:
    PERSONAL_BROWSING = "personal_browsing"
    SOCIAL_MEDIA = "social_media"
    YOUTUBE_ENTERTAINMENT = "youtube_entertainment"
    PERSONAL_EMAIL = "personal_email"
    PERSONAL_AI_USE = "personal_ai_use"
    PERSONAL_FINANCES = "personal_finances"
    PROFESSIONAL_DEVELOPMENT = "professional_development"
    ONLINE_SHOPPING = "online_shopping"    
    PERSONAL_CALENDAR = "personal_calendar"
    ENTERTAINMENT = "entertainment"
    # Work-related activities:
    SLACK = "slack"
    WORK_EMAIL = "work_email"
    ZOOM_MEETING = "zoom_meeting"
    WORK_CODING = "work_coding"
    WORK_BROWSING = "work_browsing"
    WORK_CALENDAR = "work_calendar"

class ActivitiesResponse(BaseModel):
    main_activity: Activity = Field(description="Main detected activity from the screenshot. This is the main activity that the user is engaged in. Select the most prominent activity, no matter if there are indications of other activities. For example, in a browser there might be tabs with associated to ther activities, but the main one should be the one currently visible.")
    reasoning: str = Field(description="The reasoning behind the selection of the main activity. Explain why this activity was selected based on the description of the screenshot.")

class ActivitiesResponseWithTimestamp(ActivitiesResponse):
    main_activity: Activity
    reasoning: str
    timestamp: datetime

logger = logging.getLogger(__name__)

class ActivityIdentifier:
    def __init__(self, ollama_client: Client):
        self.client = ollama_client
        
    def _describe_image(self, image_path: Path) -> Optional[str]:
        """Uses the Ollama client to generate a description of the image."""
        try:
            encoded_image = encode_image_to_base64(image_path)
            prompt = "A brief description of the user's activities based on the screenshot. Describe enough things to understand what is the main activity the user is engaged in."
            logger.debug("Calling vision model to describe image")
            response = self.client.generate(
                model="qwen3-vl:4b",
                prompt=prompt,
                images=[encoded_image],
                options={'temperature': 0, 'timeout': 30}
            )
            logger.debug("Vision model response received")
            return response.response
        except Exception as e:
            logger.error(f"Failed to describe image: {e}", exc_info=True)
            return None

    def _describe_activities(self, image_description: str) -> Optional[ActivitiesResponse]:
        prompt = f"""You are given a description of a screenshot taken from a user's computer.
It describes various elements visible on the screen.
Based on this description, identify the main activity the user is engaged in.

The user might be during their day job, taking a break, or doing personal tasks.
We want to differentiate between work-related and personal activities.
The personal categories are:
- personal_browsing : User is browsing the web for personal purposes:
- social_media : User is browsing or interacting on social media platforms.
- youtube_entertainment : User is watching videos on YouTube for entertainment.
- personal_email : User is reading or composing personal emails.
- personal_ai_use : User is interacting with AI tools (such as ChatGPT or Claude) for personal use.
- personal_finances : User is managing personal finances or banking.
- professional_development : User is engaged in activities related to their professional growth, such as learning new skills or attending webinars.
- online_shopping : User is browsing or purchasing items online.
- personal_calendar : User is checking or managing their personal calendar.
- entertainment : User is engaged in leisure activities, such as watching movies, playing games, or listening to music.
The work-related categories are:
- slack : User is actively using Slack for communication.
- work_email : User is reading or composing work-related emails.
- zoom_meeting : User is in a Zoom meeting or call.
- work_coding : User is writing or reviewing code, related to their job.
- work_browsing : User is browsing the web for work-related purposes: research, jira, documentation, etc.
- work_calendar : User is checking or managing their work calendar.

If multiple activities are detected, select only the main one and the most specific.
For example, if the user is looking at their calendar from a browser, select work_calendar or personal_calendar instead of work_browsing or personal_browsing.

The user is a software engineer, working at the moment for a audio streaming company.
This means he might be looking at technical content NOT related to his job (e.g. learning new skills). In
those cases, select professional_development as the main activity.

The description of the screenshot is as follows:
{image_description}
"""
        try:
            logger.debug("Calling classification model to identify activity")
            response = self.client.generate(
                model="qwen3:8b",
                prompt=prompt,
                format=ActivitiesResponse.model_json_schema(),
                options={'temperature': 0, 'timeout': 30},
                think=True
            )
            activities_response = ActivitiesResponse.model_validate_json(response.response)
            if response.thinking:
                logger.debug(f'Model thinking: {response.thinking}')
            logger.debug(f"Activity identified: {activities_response.main_activity}")
            return activities_response
        except Exception as e:
            logger.error(f"Failed to classify activity: {e}", exc_info=True)
            return None

    def take_screenshot_and_describe(self, monitor_id: int) -> Optional[ActivitiesResponseWithTimestamp]:
        now = datetime.now().isoformat()
        screenshot_path = None

        try:
            # Take screenshot
            logger.info(f"Taking screenshot from monitor {monitor_id}")
            with mss.mss() as sct:
                if monitor_id >= len(sct.monitors):
                    logger.error(f"Invalid monitor ID {monitor_id}. Available monitors: {len(sct.monitors) - 1}")
                    return None
                screenshot = sct.grab(sct.monitors[monitor_id])

            file_name = f"screenshots/screenshot_{monitor_id}_{now}.png"
            os.makedirs("screenshots", exist_ok=True)
            mss.tools.to_png(screenshot.rgb, screenshot.size, output=file_name)
            screenshot_path = os.path.abspath(file_name)
            logger.debug(f"Screenshot saved to {screenshot_path}")

            # Describe image
            start_time = time()
            description = self._describe_image(Path(screenshot_path))
            end_time = time()

            if description is None:
                logger.error("Failed to get image description")
                return None

            logger.info(f'Image description: {description}')
            logger.info(f"Time taken for image description: {end_time - start_time:.2f} seconds")

            # Classify activity
            start_time = time()
            activities_response = self._describe_activities(description)
            end_time = time()

            if activities_response is None:
                logger.error("Failed to classify activity")
                return None

            logger.info(f"Time taken for activity classification: {end_time - start_time:.2f} seconds")
            return ActivitiesResponseWithTimestamp(
                main_activity=activities_response.main_activity,
                reasoning=activities_response.reasoning,
                timestamp=datetime.fromisoformat(now)
            )

        except Exception as e:
            logger.error(f"Unexpected error in take_screenshot_and_describe: {e}", exc_info=True)
            return None
        finally:
            # Clean up screenshot file
            if screenshot_path and os.path.exists(screenshot_path):
                try:
                    os.remove(screenshot_path)
                    logger.debug(f"Removed screenshot file: {screenshot_path}")
                except Exception as e:
                    logger.warning(f"Failed to remove screenshot file {screenshot_path}: {e}")


def encode_image_to_base64(image_path: Path) -> str:
        """Encodes an image file to a base64 string."""
        with open(image_path, "rb") as image_file:
            return base64.b64encode(image_file.read()).decode('utf-8')
