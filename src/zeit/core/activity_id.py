from enum import Enum
from pathlib import Path
from time import time
import base64
from pydantic import BaseModel, Field
from ollama import Client
from datetime import datetime
import logging
from typing import Dict, List, Optional
from opik import track, opik_context

from zeit.core.screen import MultiScreenCapture
from zeit.core.active_window import get_active_screen_number
from zeit.core.config import ModelsConfig
from zeit.core.prompts import (
    MULTI_SCREEN_DESCRIPTION_PROMPT,
    ACTIVE_SCREEN_HINT_TEMPLATE,
    ACTIVE_SCREEN_HINT_FALLBACK,
    SINGLE_SCREEN_DESCRIPTION_PROMPT,
    ACTIVITY_CLASSIFICATION_PROMPT,
)


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

    def is_work_activity(self) -> bool:
        return self in {
            Activity.SLACK,
            Activity.WORK_EMAIL,
            Activity.ZOOM_MEETING,
            Activity.WORK_CODING,
            Activity.WORK_BROWSING,
            Activity.WORK_CALENDAR,
        }


class ExtendedActivity(str, Enum):
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
    SLACK = "slack"
    WORK_EMAIL = "work_email"
    ZOOM_MEETING = "zoom_meeting"
    WORK_CODING = "work_coding"
    WORK_BROWSING = "work_browsing"
    WORK_CALENDAR = "work_calendar"
    IDLE = "idle"

    def is_work_activity(self) -> bool:
        return self in {
            ExtendedActivity.SLACK,
            ExtendedActivity.WORK_EMAIL,
            ExtendedActivity.ZOOM_MEETING,
            ExtendedActivity.WORK_CODING,
            ExtendedActivity.WORK_BROWSING,
            ExtendedActivity.WORK_CALENDAR,
        }


class MultiScreenDescription(BaseModel):
    """Structured output from vision model for multi-screen screenshots."""
    primary_screen: int = Field(
        description="The screen number (1, 2, 3, etc.) that is the PRIMARY/ACTIVE screen where the user is currently focused."
    )
    main_activity_description: str = Field(
        description="A brief description of the user's main activity based on the PRIMARY screen. Describe enough to understand what the main activity the user is engaged in."
    )
    secondary_context: Optional[str] = Field(
        default=None,
        description="Brief description of what's visible on secondary screens for context. Set to null if there's nothing notable or only one screen."
    )


class ActivitiesResponse(BaseModel):
    main_activity: Activity = Field(
        description="Main detected activity from the screenshot. This is the main activity that the user is engaged in. Select the most prominent activity, no matter if there are indications of other activities. For example, in a browser there might be tabs with associated to ther activities, but the main one should be the one currently visible."
    )
    reasoning: str = Field(
        description="The reasoning behind the selection of the main activity. Explain why this activity was selected based on the description of the screenshot."
    )
    secondary_context: Optional[str] = Field(
        default=None,
        description="Brief description of activities visible on secondary screens, if any. This provides context about what else the user might be doing."
    )


class ActivitiesResponseWithTimestamp(ActivitiesResponse):
    main_activity: Activity
    reasoning: str
    secondary_context: Optional[str] = None
    timestamp: datetime


logger = logging.getLogger(__name__)


class ActivityIdentifier:
    def __init__(self, ollama_client: Client, models_config: ModelsConfig):
        self.client = ollama_client
        self.vlm = models_config.vision
        self.llm = models_config.text

    @track(tags=["ollama", "python-library"])
    def _describe_images(
        self, screenshot_paths: Dict[int, Path], active_screen_hint: Optional[int] = None
    ) -> Optional[MultiScreenDescription]:
        """Uses the Ollama client to generate a structured description of screen images.
        
        Args:
            screenshot_paths: Dict mapping screen number to screenshot path
            active_screen_hint: Optional screen number (1-based) from native detection
        """
        try:
            # Encode all images in order
            encoded_images: List[str] = []
            for monitor_id in sorted(screenshot_paths.keys()):
                encoded_images.append(encode_image_to_base64(screenshot_paths[monitor_id]))

            is_multi_screen = len(encoded_images) > 1
            
            if is_multi_screen:
                # Build prompt with active screen hint
                if active_screen_hint is not None:
                    hint = ACTIVE_SCREEN_HINT_TEMPLATE.format(screen_number=active_screen_hint)
                else:
                    hint = ACTIVE_SCREEN_HINT_FALLBACK
                prompt = MULTI_SCREEN_DESCRIPTION_PROMPT.format(active_screen_hint=hint)
            else:
                prompt = SINGLE_SCREEN_DESCRIPTION_PROMPT

            logger.debug(f"Calling vision model to describe {len(encoded_images)} image(s)")

            # Use structured output for multi-screen, plain text for single screen
            if is_multi_screen:
                response = self.client.generate(
                    model=self.vlm,
                    prompt=prompt,
                    images=encoded_images,
                    format=MultiScreenDescription.model_json_schema(),
                    options={"temperature": 0, "timeout": 30},
                )
            else:
                response = self.client.generate(
                    model=self.vlm,
                    prompt=prompt,
                    images=encoded_images,
                    options={"temperature": 0, "timeout": 30},
                )

            opik_context.update_current_span(
                metadata={
                    "model": response["model"],
                    "eval_duration": response["eval_duration"],
                    "load_duration": response["load_duration"],
                    "prompt_eval_duration": response["prompt_eval_duration"],
                    "prompt_eval_count": response["prompt_eval_count"],
                    "done": response["done"],
                    "done_reason": response["done_reason"],
                    "screen_count": len(screenshot_paths),
                    "active_screen_detected": active_screen_hint,
                },
                usage={
                    "completion_tokens": response["eval_count"],
                    "prompt_tokens": response["prompt_eval_count"],
                    "total_tokens": response["eval_count"]
                    + response["prompt_eval_count"],
                },
            )
            logger.debug("Vision model response received")
            
            if is_multi_screen:
                thinking = response.thinking
                if not thinking:
                    raise RuntimeError("Expected thinking output from vision model for multi-screen analysis")
                return MultiScreenDescription.model_validate_json(thinking)
            else:
                # Wrap single-screen plain text in structured format
                return MultiScreenDescription(
                    primary_screen=1,
                    main_activity_description=response.response,
                    secondary_context=None
                )
        except Exception as e:
            logger.error(f"Failed to describe images: {e}", exc_info=True)
            return None

    @track(tags=["ollama", "python-library"])
    def _describe_activities(
        self, image_description: str, secondary_context: Optional[str] = None
    ) -> Optional[ActivitiesResponse]:
        secondary_context_section = ""
        if secondary_context:
            secondary_context_section = f"\n\nAdditionally, the following was visible on secondary screens (for context only, focus on the main activity):\n{secondary_context}\n"

        prompt = ACTIVITY_CLASSIFICATION_PROMPT.format(
            image_description=image_description,
            secondary_context_section=secondary_context_section
        )
        try:
            logger.debug("Calling classification model to identify activity")
            response = self.client.generate(
                model=self.llm,
                prompt=prompt,
                format=ActivitiesResponse.model_json_schema(),
                options={"temperature": 0, "timeout": 30},
                think=True,
            )
            opik_context.update_current_span(
                metadata={
                    "model": response["model"],
                    "eval_duration": response["eval_duration"],
                    "load_duration": response["load_duration"],
                    "prompt_eval_duration": response["prompt_eval_duration"],
                    "prompt_eval_count": response["prompt_eval_count"],
                    "done": response["done"],
                    "done_reason": response["done_reason"],
                },
                usage={
                    "completion_tokens": response["eval_count"],
                    "prompt_tokens": response["prompt_eval_count"],
                    "total_tokens": response["eval_count"]
                    + response["prompt_eval_count"],
                },
            )
            activities_response = ActivitiesResponse.model_validate_json(
                response.response
            )
            if response.thinking:
                logger.debug(f"Model thinking: {response.thinking}")
            logger.debug(f"Activity identified: {activities_response.main_activity}")
            return activities_response
        except Exception as e:
            logger.error(f"Failed to classify activity: {e}", exc_info=True)
            return None

    def take_screenshot_and_describe(self) -> Optional[ActivitiesResponseWithTimestamp]:
        """Capture all screens and identify the main activity."""
        now = datetime.now()

        with MultiScreenCapture(now) as screenshot_paths:
            logger.info(f"Captured {len(screenshot_paths)} screen(s)")
            
            # Detect active screen using native macOS APIs
            active_screen_hint: Optional[int] = None
            if len(screenshot_paths) > 1:
                active_screen_hint = get_active_screen_number()
                logger.info(f"Native detection: active screen is {active_screen_hint}")
            
            start_time = time()
            screen_description = self._describe_images(screenshot_paths, active_screen_hint)
            end_time = time()

        if screen_description is None:
            logger.error("Failed to get image description")
            return None

        logger.info(f"Primary screen: {screen_description.primary_screen}")
        logger.info(f"Main activity description: {screen_description.main_activity_description}")
        if screen_description.secondary_context:
            logger.info(f"Secondary context: {screen_description.secondary_context}")
        logger.info(
            f"Time taken for image description: {end_time - start_time:.2f} seconds"
        )

        # Classify activity
        start_time = time()
        activities_response = self._describe_activities(
            screen_description.main_activity_description,
            screen_description.secondary_context
        )
        end_time = time()

        if activities_response is None:
            logger.error("Failed to classify activity")
            return None

        logger.info(
            f"Time taken for activity classification: {end_time - start_time:.2f} seconds"
        )
        return ActivitiesResponseWithTimestamp(
            main_activity=activities_response.main_activity,
            reasoning=activities_response.reasoning,
            secondary_context=screen_description.secondary_context,
            timestamp=now,
        )

def encode_image_to_base64(image_path: Path) -> str:
    """Encodes an image file to a base64 string."""
    with open(image_path, "rb") as image_file:
        return base64.b64encode(image_file.read()).decode("utf-8")
