import base64
import logging
from collections.abc import Callable
from datetime import datetime
from functools import wraps
from pathlib import Path
from time import time
from typing import Any, TypeVar

from ollama import Client

from zeit.core.active_window import get_active_screen_number
from zeit.core.config import ModelsConfig
from zeit.core.models import (
    ActivitiesResponse,
    ActivitiesResponseWithTimestamp,
    MultiScreenDescription,
)
from zeit.core.prompts import (
    ACTIVE_SCREEN_HINT_FALLBACK,
    ACTIVE_SCREEN_HINT_TEMPLATE,
    ACTIVITY_CLASSIFICATION_PROMPT,
    MULTI_SCREEN_DESCRIPTION_PROMPT,
    SINGLE_SCREEN_DESCRIPTION_PROMPT,
)
from zeit.core.screen import MultiScreenCapture

logger = logging.getLogger(__name__)

# Make opik optional - it has heavy dependencies that complicate packaging
# Lazy-loaded to avoid ~1.3s import time on CLI startup
F = TypeVar("F", bound=Callable[..., Any])
_opik_loaded = False
_opik_available = False
_opik_context: Any = None
_opik_track: Any = None


def _load_opik() -> bool:
    """Lazy-load opik on first use. Returns True if available."""
    global _opik_loaded, _opik_available, _opik_context, _opik_track
    if _opik_loaded:
        return _opik_available
    _opik_loaded = True
    try:
        from opik import opik_context as ctx
        from opik import track as trk

        _opik_available = True
        _opik_context = ctx
        _opik_track = trk
    except ImportError:
        _opik_available = False
    return _opik_available


def get_opik_context() -> Any:
    """Get opik_context, lazy-loading opik if needed."""
    if _load_opik():
        return _opik_context
    return None


def track(**kwargs: Any) -> Callable[[F], F]:
    """Wrapper for opik.track that becomes a no-op when opik is unavailable.

    The opik import is deferred until the decorated function is actually called,
    not when the decorator is applied (class definition time).
    """

    def decorator(func: F) -> F:
        @wraps(func)
        def wrapper(*args: Any, **kw: Any) -> Any:
            # Lazy load opik on first actual call, not at decoration time
            if _load_opik() and _opik_track is not None:
                # Replace this wrapper with the real opik-tracked function
                tracked_func = _opik_track(**kwargs)(func)
                # Cache it on the instance to avoid re-wrapping
                return tracked_func(*args, **kw)
            return func(*args, **kw)

        return wrapper  # type: ignore[return-value]

    return decorator


def encode_image_to_base64(image_path: Path) -> str:
    """Encode image file to base64 string."""
    with open(image_path, "rb") as f:
        return base64.b64encode(f.read()).decode("utf-8")


class ActivityIdentifier:
    def __init__(self, ollama_client: Client, models_config: ModelsConfig) -> None:
        self.client = ollama_client
        self.vlm = models_config.vision
        self.llm = models_config.text

    @track(tags=["ollama", "python-library"])
    def _describe_images(
        self, screenshot_paths: dict[int, Path], active_screen_hint: int | None = None
    ) -> MultiScreenDescription | None:
        """Uses the Ollama client to generate a structured description of screen images.

        Args:
            screenshot_paths: Dict mapping screen number to screenshot path
            active_screen_hint: Optional screen number (1-based) from native detection
        """
        try:
            # Encode all images in order
            encoded_images: list[str] = []
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
                    think=True,
                )
            else:
                response = self.client.generate(
                    model=self.vlm,
                    prompt=prompt,
                    images=encoded_images,
                    options={"temperature": 0, "timeout": 30},
                )

            opik_ctx = get_opik_context()
            if opik_ctx is not None:
                opik_ctx.update_current_span(
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
                        "total_tokens": response["eval_count"] + response["prompt_eval_count"],
                    },
                )
            logger.debug("Vision model response received")

            if is_multi_screen:
                thinking = response.thinking
                if not thinking:
                    raise RuntimeError(
                        "Expected thinking output from vision model for multi-screen analysis"
                    )
                return MultiScreenDescription.model_validate_json(thinking)
            # Wrap single-screen plain text in structured format
            return MultiScreenDescription(
                primary_screen=1,
                main_activity_description=response.response,
                secondary_context=None,
            )
        except Exception as e:
            logger.error(f"Failed to describe images: {e}", exc_info=True)
            return None

    @track(tags=["ollama", "python-library"])
    def _describe_activities(
        self, image_description: str, secondary_context: str | None = None
    ) -> ActivitiesResponse | None:
        secondary_context_section = ""
        if secondary_context:
            secondary_context_section = (
                f"\n\nAdditionally, the following was visible on secondary screens "
                f"(for context only, focus on the main activity):\n{secondary_context}\n"
            )

        prompt = ACTIVITY_CLASSIFICATION_PROMPT.format(
            image_description=image_description, secondary_context_section=secondary_context_section
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
            opik_ctx = get_opik_context()
            if opik_ctx is not None:
                opik_ctx.update_current_span(
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
                        "total_tokens": response["eval_count"] + response["prompt_eval_count"],
                    },
                )
            activities_response = ActivitiesResponse.model_validate_json(response.response)
            if response.thinking:
                logger.debug(f"Model thinking: {response.thinking}")
            logger.debug(f"Activity identified: {activities_response.main_activity}")
            return activities_response
        except Exception as e:
            logger.error(f"Failed to classify activity: {e}", exc_info=True)
            return None

    def take_screenshot_and_describe(self) -> ActivitiesResponseWithTimestamp | None:
        """Capture all screens and identify the main activity."""
        now = datetime.now()

        with MultiScreenCapture(now) as screenshot_paths:
            logger.info(f"Captured {len(screenshot_paths)} screen(s)")

            # Try to get the active screen number from the native API
            active_screen = get_active_screen_number()
            if active_screen:
                logger.debug(f"Active screen detected: {active_screen}")

            start_describe = time()
            description = self._describe_images(screenshot_paths, active_screen_hint=active_screen)
            elapsed_describe = time() - start_describe
            logger.debug(f"Image description took {elapsed_describe:.2f}s")

            if description is None:
                logger.error("Failed to describe images")
                return None

            logger.info(f"Primary screen: {description.primary_screen}")
            logger.debug(f"Activity description: {description.main_activity_description}")
            if description.secondary_context:
                logger.debug(f"Secondary context: {description.secondary_context}")

            start_classify = time()
            activities_response = self._describe_activities(
                description.main_activity_description,
                secondary_context=description.secondary_context,
            )
            elapsed_classify = time() - start_classify
            logger.debug(f"Activity classification took {elapsed_classify:.2f}s")

            if activities_response is None:
                logger.error("Failed to classify activity")
                return None

            return ActivitiesResponseWithTimestamp(
                main_activity=activities_response.main_activity,
                reasoning=activities_response.reasoning,
                timestamp=now,
            )
