import logging
from datetime import datetime

from ollama import Client
from pydantic import BaseModel

from zeit.core.activity_types import ExtendedActivity
from zeit.core.prompts import DAY_SUMMARIZATION_PROMPT
from zeit.data.db import ActivityEntry
from zeit.processing.activity_summarization import ActivityGroup, build_condensed_summary

logger = logging.getLogger(__name__)


class DaySummary(BaseModel):
    summary: str
    start_time: datetime
    end_time: datetime


class DaySummarizer:
    def __init__(self, ollama_client: Client, llm: str) -> None:
        self.client = ollama_client
        self.llm = llm

    def _format_time_range(self, start: datetime, end: datetime) -> str:
        """Format a time range like '09:15-09:45' or just '09:15' if single minute."""
        if start == end:
            return start.strftime("%H:%M")
        return f"{start.strftime('%H:%M')}-{end.strftime('%H:%M')}"

    def _format_group(self, group: ActivityGroup) -> str:
        """Format an activity group for the prompt."""
        time_range = self._format_time_range(group.start_time, group.end_time)
        reasoning = group.merged_reasoning or "No description"
        activity_name = group.activity.value.replace("_", " ")
        return f'{time_range} - {activity_name} ({group.duration_minutes} min): "{reasoning}"'

    def summarize(self, activities: list[ActivityEntry]) -> DaySummary | None:
        non_idle = [a for a in activities if a.activity != ExtendedActivity.IDLE]

        if not non_idle:
            return None

        logger.info(f"Starting summarization with {len(non_idle)} non-idle activities")

        # Build condensed summary with grouped activities and merged reasonings
        condensed = build_condensed_summary(
            entries=activities,
            client=self.client,
            llm=self.llm,
        )

        logger.info(
            f"Condensed {condensed.original_entry_count} activities "
            f"into {condensed.condensed_entry_count} groups"
        )

        # Format condensed activities for prompt
        activities_text = "\n".join(self._format_group(group) for group in condensed.groups)

        # Format percentage breakdown
        percentage_text = "\n".join(
            f"- {p.activity.value.replace('_', ' ')}: {p.percentage:.1f}%"
            for p in condensed.percentage_breakdown
        )

        # Build the final prompt
        prompt = DAY_SUMMARIZATION_PROMPT.format(
            percentage_breakdown=percentage_text,
            activities_text=activities_text,
        )

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
