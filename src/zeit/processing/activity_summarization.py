import logging
from datetime import datetime

from ollama import Client
from pydantic import BaseModel, Field

from zeit.core.activity_types import ExtendedActivity
from zeit.core.prompts import MERGE_REASONINGS_PROMPT
from zeit.data.db import ActivityEntry

logger = logging.getLogger(__name__)


class ActivityWithPercentage(BaseModel):
    """Represents an activity along with its occurrence count."""

    activity: ExtendedActivity = Field(description="The activity type")
    percentage: float = Field(description="Percentage of total activities")


class ActivityGroup(BaseModel):
    """A group of consecutive activities of the same type."""

    activity: ExtendedActivity = Field(description="The activity type")
    start_time: datetime = Field(description="Timestamp of the first activity in the group")
    end_time: datetime = Field(description="Timestamp of the last activity in the group")
    duration_minutes: int = Field(description="Number of minutes this group spans")
    reasonings: list[str] = Field(description="All individual reasonings from grouped activities")
    merged_reasoning: str | None = Field(
        default=None, description="LLM-merged reasoning if group has multiple entries"
    )


class CondensedActivitySummary(BaseModel):
    """Container for the full condensed activity data."""

    groups: list[ActivityGroup] = Field(description="Chronologically ordered activity groups")
    percentage_breakdown: list[ActivityWithPercentage] = Field(
        description="Activity percentages sorted by frequency"
    )
    total_active_minutes: int = Field(description="Total non-idle minutes tracked")
    original_entry_count: int = Field(description="Number of activities before condensation")
    condensed_entry_count: int = Field(description="Number of activity groups after condensation")


def compute_summary(entries: list[ActivityEntry]) -> list[ActivityWithPercentage]:
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
        ActivityWithPercentage(activity=activity, percentage=(count / total_activities) * 100)
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
        merged_reasoning=None,
    )


def merge_reasonings(
    reasonings: list[str],
    activity: ExtendedActivity,
    duration_minutes: int,
    client: Client,
    llm: str,
) -> str:
    """Use LLM to merge multiple minute-by-minute reasonings into one.

    Args:
        reasonings: List of individual reasonings from consecutive activities
        activity: The activity type (for context in the prompt)
        duration_minutes: Number of minutes the activity spans
        client: Ollama client
        llm: Model name to use

    Returns:
        A single merged reasoning string
    """
    reasonings_list = "\n".join(f"- {r}" for r in reasonings)
    prompt = MERGE_REASONINGS_PROMPT.format(
        activity_name=activity.value.replace("_", " "),
        duration=duration_minutes,
        reasonings_list=reasonings_list,
    )

    try:
        logger.debug(f"Merging {len(reasonings)} reasonings for {activity.value}")
        response = client.generate(
            model=llm,
            prompt=prompt,
            options={"temperature": 0.3},
        )
        return response.response.strip()
    except Exception as e:
        logger.error(f"Failed to merge reasonings: {e}", exc_info=True)
        # Fallback: just return the first reasoning
        # TODO: don't fallback and raise an error instead?
        return reasonings[0] if reasonings else "No description"


def build_condensed_summary(
    entries: list[ActivityEntry],
    client: Client,
    llm: str,
) -> CondensedActivitySummary:
    """Build a complete condensed summary from raw activity entries.

    If client and llm are provided, will use LLM to merge reasonings for groups
    with multiple entries. Otherwise, just concatenates reasonings.

    Args:
        entries: List of ActivityEntry
        client: Optional Ollama client for reasoning merging
        llm: Optional model name for reasoning merging

    Returns:
        CondensedActivitySummary with grouped activities and percentages
    """
    non_idle = [e for e in entries if e.activity != ExtendedActivity.IDLE]
    groups = group_consecutive_activities(entries)
    logger.info(f"Grouped {len(non_idle)} activities into {len(groups)} groups")

    # Merge reasonings for groups with multiple entries
    for group in groups:
        if len(group.reasonings) > 1:
            group.merged_reasoning = merge_reasonings(
                group.reasonings, group.activity, group.duration_minutes, client, llm
            )
        elif group.reasonings:
            # Single reasoning or no LLM - just use the first one
            group.merged_reasoning = group.reasonings[0]

    percentage_breakdown = compute_summary(entries)

    return CondensedActivitySummary(
        groups=groups,
        percentage_breakdown=percentage_breakdown,
        total_active_minutes=len(non_idle),
        original_entry_count=len(non_idle),
        condensed_entry_count=len(groups),
    )
