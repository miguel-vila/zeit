"""Activity statistics computation.

This module provides reusable functions for computing activity statistics,
used by both the CLI and MCP app.
"""

from pydantic import BaseModel, Field

from zeit.core.activity_types import ExtendedActivity
from zeit.data.db import ActivityEntry

# Activity categories
PERSONAL_ACTIVITIES = {
    ExtendedActivity.PERSONAL_BROWSING,
    ExtendedActivity.SOCIAL_MEDIA,
    ExtendedActivity.YOUTUBE_ENTERTAINMENT,
    ExtendedActivity.PERSONAL_EMAIL,
    ExtendedActivity.PERSONAL_AI_USE,
    ExtendedActivity.PERSONAL_FINANCES,
    ExtendedActivity.PROFESSIONAL_DEVELOPMENT,
    ExtendedActivity.ONLINE_SHOPPING,
    ExtendedActivity.PERSONAL_CALENDAR,
    ExtendedActivity.ENTERTAINMENT,
}

WORK_ACTIVITIES = {
    ExtendedActivity.SLACK,
    ExtendedActivity.WORK_EMAIL,
    ExtendedActivity.ZOOM_MEETING,
    ExtendedActivity.WORK_CODING,
    ExtendedActivity.WORK_BROWSING,
    ExtendedActivity.WORK_CALENDAR,
}


class ActivityStat(BaseModel):
    """Statistics for a single activity type."""

    activity: str = Field(description="Activity type name")
    count: int = Field(description="Number of occurrences")
    percentage: float = Field(description="Percentage of total activities")
    category: str = Field(description="Category: 'work', 'personal', or 'system'")


class DayStats(BaseModel):
    """Complete statistics for a day's activities."""

    date: str = Field(description="Date in YYYY-MM-DD format")
    total_samples: int = Field(description="Total number of activity samples")
    activities: list[ActivityStat] = Field(
        description="Per-activity statistics, sorted by percentage descending"
    )
    work_percentage: float = Field(description="Percentage of work activities")
    personal_percentage: float = Field(description="Percentage of personal activities")
    idle_percentage: float = Field(description="Percentage of idle time")
    work_count: int = Field(description="Number of work activity samples")
    personal_count: int = Field(description="Number of personal activity samples")
    idle_count: int = Field(description="Number of idle samples")


def get_activity_category(activity: ExtendedActivity) -> str:
    """Get the category for an activity type."""
    if activity in WORK_ACTIVITIES:
        return "work"
    if activity in PERSONAL_ACTIVITIES:
        return "personal"
    return "system"


def compute_day_stats(date_str: str, entries: list[ActivityEntry]) -> DayStats:
    """Compute statistics for a day's activities.

    Args:
        date_str: Date in YYYY-MM-DD format
        entries: List of activity entries for the day

    Returns:
        DayStats with complete breakdown
    """
    total = len(entries)

    if total == 0:
        return DayStats(
            date=date_str,
            total_samples=0,
            activities=[],
            work_percentage=0.0,
            personal_percentage=0.0,
            idle_percentage=0.0,
            work_count=0,
            personal_count=0,
            idle_count=0,
        )

    # Count activities
    counts: dict[ExtendedActivity, int] = {}
    for entry in entries:
        counts[entry.activity] = counts.get(entry.activity, 0) + 1

    # Build per-activity stats
    activity_stats: list[ActivityStat] = []
    work_count = 0
    personal_count = 0
    idle_count = 0

    for activity, count in counts.items():
        percentage = (count / total) * 100
        category = get_activity_category(activity)

        activity_stats.append(
            ActivityStat(
                activity=activity.value,
                count=count,
                percentage=percentage,
                category=category,
            )
        )

        if category == "work":
            work_count += count
        elif category == "personal":
            personal_count += count
        else:
            idle_count += count

    # Sort by percentage descending
    activity_stats.sort(key=lambda x: -x.percentage)

    return DayStats(
        date=date_str,
        total_samples=total,
        activities=activity_stats,
        work_percentage=(work_count / total) * 100,
        personal_percentage=(personal_count / total) * 100,
        idle_percentage=(idle_count / total) * 100,
        work_count=work_count,
        personal_count=personal_count,
        idle_count=idle_count,
    )


def get_day_stats(date_str: str) -> DayStats | None:
    """Get statistics for a specific day from the database.

    Args:
        date_str: Date in YYYY-MM-DD format

    Returns:
        DayStats if data exists, None otherwise
    """
    from zeit.data.db import DatabaseManager

    with DatabaseManager() as db:
        day_record = db.get_day_record(date_str)

        if day_record is None:
            return None

        return compute_day_stats(date_str, day_record.activities)


def get_available_dates() -> list[str]:
    """Get list of dates with activity data.

    Returns:
        List of dates in YYYY-MM-DD format, sorted descending
    """
    from zeit.data.db import DatabaseManager

    with DatabaseManager() as db:
        return [date for date, _ in db.get_all_days()]
