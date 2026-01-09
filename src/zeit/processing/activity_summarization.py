import logging
from datetime import datetime

from pydantic import BaseModel, Field

from zeit.core.activity_types import ExtendedActivity
from zeit.data.db import ActivityEntry

logger = logging.getLogger(__name__)


class ActivitySummary(BaseModel):
    """Represents an activity with its percentage and approximate time."""

    activity: ExtendedActivity = Field(description="The activity type")
    percentage: float = Field(description="Percentage of total activities")
    approx_minutes: int = Field(description="Approximate time spent in minutes")


class ActivityGroup(BaseModel):
    """A group of consecutive activities of the same type."""

    activity: ExtendedActivity = Field(description="The activity type")
    start_time: datetime = Field(description="Timestamp of the first activity in the group")
    end_time: datetime = Field(description="Timestamp of the last activity in the group")
    duration_minutes: int = Field(description="Number of minutes this group spans")
    reasonings: list[str] = Field(description="All individual reasonings from grouped activities")


class CondensedActivitySummary(BaseModel):
    """Container for the full condensed activity data."""

    groups: list[ActivityGroup] = Field(description="Chronologically ordered activity groups")
    percentage_breakdown: list[ActivitySummary] = Field(
        description="Activity percentages sorted by frequency"
    )
    total_active_minutes: int = Field(description="Total non-idle minutes tracked")
    original_entry_count: int = Field(description="Number of activities before condensation")
    condensed_entry_count: int = Field(description="Number of activity groups after condensation")


def compute_summary(entries: list[ActivityEntry]) -> list[ActivitySummary]:
    """Compute a summary of activities from a list of ActivityEntry."""
    summary: dict[ExtendedActivity, int] = {}
    for entry in entries:
        activity_name = entry.activity
        if activity_name == ExtendedActivity.IDLE:
            continue
        summary[activity_name] = summary.get(activity_name, 0) + 1
    sorted_summary = sorted(summary.items(), key=lambda x: -x[1])
    total_activities = sum(summary.values())
    if total_activities == 0:
        return []
    return [
        ActivitySummary(
            activity=activity,
            percentage=(count / total_activities) * 100,
            approx_minutes=count,
        )
        for activity, count in sorted_summary
    ]


def group_consecutive_activities(entries: list[ActivityEntry]) -> list[ActivityGroup]:
    """Group consecutive activities of the same type (excluding IDLE).

    Args:
        entries: List of ActivityEntry, expected to be chronologically ordered

    Returns:
        List of ActivityGroup, one per consecutive sequence of same activity type
    """
    non_idle = [e for e in entries if e.activity != ExtendedActivity.IDLE]
    if not non_idle:
        return []

    groups: list[ActivityGroup] = []
    current_entries: list[ActivityEntry] = [non_idle[0]]

    for entry in non_idle[1:]:
        if entry.activity == current_entries[0].activity:
            current_entries.append(entry)
        else:
            groups.append(_create_group(current_entries))
            current_entries = [entry]

    # Don't forget the last group
    groups.append(_create_group(current_entries))
    return groups


def _create_group(entries: list[ActivityEntry]) -> ActivityGroup:
    """Create an ActivityGroup from a list of consecutive entries of the same type."""
    start_time = datetime.fromisoformat(entries[0].timestamp)
    end_time = datetime.fromisoformat(entries[-1].timestamp)
    reasonings = [e.reasoning for e in entries if e.reasoning]
    return ActivityGroup(
        activity=entries[0].activity,
        start_time=start_time,
        end_time=end_time,
        duration_minutes=len(entries),
        reasonings=reasonings,
    )


def build_condensed_summary(entries: list[ActivityEntry]) -> CondensedActivitySummary:
    """Build a complete condensed summary from raw activity entries.

    Groups consecutive activities of the same type and computes percentage breakdown.

    Args:
        entries: List of ActivityEntry

    Returns:
        CondensedActivitySummary with grouped activities and percentages
    """
    non_idle = [e for e in entries if e.activity != ExtendedActivity.IDLE]
    groups = group_consecutive_activities(entries)
    logger.info(f"Grouped {len(non_idle)} activities into {len(groups)} groups")

    percentage_breakdown = compute_summary(entries)

    return CondensedActivitySummary(
        groups=groups,
        percentage_breakdown=percentage_breakdown,
        total_active_minutes=len(non_idle),
        original_entry_count=len(non_idle),
        condensed_entry_count=len(groups),
    )
