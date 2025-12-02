from typing import List
from pydantic import BaseModel, Field

from src.zeit.core.activity_id import ExtendedActivity
from src.zeit.data.db import ActivityEntry

class ActivityWithPercentage(BaseModel):
    """Represents an activity along with its occurrence count."""
    activity: ExtendedActivity = Field(description="The activity type")
    percentage: float = Field(description="Percentage of total activities")

def compute_summary(entries: List[ActivityEntry]) -> List[ActivityWithPercentage]:
    """Compute a summary of activities from a list of ActivityEntry."""
    summary: dict[ExtendedActivity, int] = {}
    for entry in entries:
        activity_name = entry.activity
        summary[activity_name] = summary.get(activity_name, 0) + 1
    sorted_summary = sorted(summary.items(), key=lambda x: -x[1])
    total_activities = sum(summary.values())
    return [ ActivityWithPercentage(activity=activity, percentage=(count / total_activities) * 100) for activity, count in sorted_summary ]
