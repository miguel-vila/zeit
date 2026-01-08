"""Pydantic models for LLM responses in Zeit."""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field

from zeit.core.activity_types import Activity


class MultiScreenDescription(BaseModel):
    """Structured output from vision model for multi-screen screenshots."""

    primary_screen: int = Field(
        description=(
            "The screen number (1, 2, 3, etc.) that is the PRIMARY/ACTIVE screen "
            "where the user is currently focused."
        )
    )
    main_activity_description: str = Field(
        description=(
            "A brief description of the user's main activity based on the PRIMARY screen. "
            "Describe enough to understand what the main activity the user is engaged in."
        )
    )
    secondary_context: Optional[str] = Field(
        default=None,
        description=(
            "Brief description of what's visible on secondary screens for context. "
            "Set to null if there's nothing notable or only one screen."
        ),
    )


class ActivitiesResponse(BaseModel):
    """Structured output from classification model."""

    main_activity: Activity = Field(
        description=(
            "Main detected activity from the screenshot. This is the main activity that the "
            "user is engaged in. Select the most prominent activity, no matter if there are "
            "indications of other activities. For example, in a browser there might be tabs "
            "with associated to ther activities, but the main one should be the one currently "
            "visible."
        )
    )
    reasoning: str = Field(
        description=(
            "The reasoning behind the selection of the main activity. Explain why this "
            "activity was selected based on the description of the screenshot."
        )
    )
    secondary_context: Optional[str] = Field(
        default=None,
        description=(
            "Brief description of activities visible on secondary screens, if any. "
            "This provides context about what else the user might be doing."
        ),
    )


class ActivitiesResponseWithTimestamp(ActivitiesResponse):
    """ActivitiesResponse with added timestamp for storage."""

    main_activity: Activity
    reasoning: str
    secondary_context: Optional[str] = None
    timestamp: datetime
