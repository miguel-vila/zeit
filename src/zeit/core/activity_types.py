"""Activity type enums for Zeit."""

from enum import Enum


class Activity(str, Enum):
    """Activity types for LLM classification (excludes IDLE which is system-detected)."""

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
    """Activity types including IDLE for storage and display."""

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
