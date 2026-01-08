import logging
from datetime import datetime

from ollama import Client
from pydantic import BaseModel

from zeit.core.activity_types import ExtendedActivity
from zeit.data.db import ActivityEntry

logger = logging.getLogger(__name__)


class DaySummary(BaseModel):
    summary: str
    start_time: datetime
    end_time: datetime


class DaySummarizer:
    def __init__(self, ollama_client: Client, llm: str):
        self.client = ollama_client
        self.llm = llm

    def summarize(self, activities: list[ActivityEntry]) -> DaySummary | None:
        non_idle = [a for a in activities if a.activity != ExtendedActivity.IDLE]

        if not non_idle:
            return None

        formatted_lines = []
        for activity in non_idle:
            timestamp = datetime.fromisoformat(activity.timestamp)
            time_str = timestamp.strftime("%H:%M")
            reasoning = activity.reasoning or "No description"
            formatted_lines.append(f'{time_str} - {activity.activity.value}: "{reasoning}"')

        activities_text = "\n".join(formatted_lines)

        prompt = f"""This is a list of the activities that the user did during the day, minute by minute. There might be some gaps because of idle time.

{activities_text}

Summarize the user's day qualitatively.
Describe what they focused on, how their time was distributed, and any notable patterns.
Don't make value judgments (either positive or negative).
Don't talk about balance unless there's numerical evidence that really justifies that description.
Just summarize the activities in an objective manner."""

        try:
            logger.debug("Calling LLM to summarize day activities")
            response = self.client.generate(
                model=self.llm,
                prompt=prompt,
                options={"temperature": 0.7},
            )
        except Exception as e:
            logger.error(f"Failed to summarize day activities: {e}", exc_info=True)
            return None

        start_time = datetime.fromisoformat(non_idle[0].timestamp)
        end_time = datetime.fromisoformat(non_idle[-1].timestamp)

        logger.debug(f"Day summary generated for {start_time.date()}")
        return DaySummary(
            summary=response.response,
            start_time=start_time,
            end_time=end_time,
        )
