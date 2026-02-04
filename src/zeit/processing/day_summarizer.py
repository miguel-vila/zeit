import logging
from datetime import datetime

from pydantic import BaseModel

from zeit.core.activity_types import ExtendedActivity
from zeit.core.llm_provider import LLMProvider
from zeit.core.prompts import DAY_SUMMARIZATION_PROMPT, DAY_SUMMARIZATION_WITH_OBJECTIVES_PROMPT
from zeit.data.db import ActivityEntry, DayObjectives
from zeit.processing.activity_summarization import ActivityGroup, build_condensed_summary

logger = logging.getLogger(__name__)


class DaySummary(BaseModel):
    summary: str
    percentages_breakdown: str
    start_time: datetime
    end_time: datetime


class DaySummarizer:
    def __init__(self, provider: LLMProvider) -> None:
        self.provider = provider

    def _format_time_range(self, start: datetime, end: datetime) -> str:
        """Format a time range like '09:15-09:45' or just '09:15' if single minute."""
        if start == end:
            return start.strftime("%H:%M")
        return f"{start.strftime('%H:%M')}-{end.strftime('%H:%M')}"

    def _format_group(self, group: ActivityGroup) -> str:
        """Format an activity group for the prompt."""
        time_range = self._format_time_range(group.start_time, group.end_time)
        reasoning = "; ".join(group.reasonings) if group.reasonings else "No description"
        activity_name = group.activity.value.replace("_", " ")
        return f'{time_range} - {activity_name} ({group.duration_minutes} min): "{reasoning}"'

    def _format_objectives_section(self, objectives: DayObjectives) -> str:
        """Format secondary objectives section for the prompt."""
        if not objectives.secondary_objectives:
            return ""
        lines = ["**Secondary Objectives:**"]
        for obj in objectives.secondary_objectives:
            lines.append(f"- {obj}")
        return "\n".join(lines)

    def summarize(
        self,
        activities: list[ActivityEntry],
        objectives: DayObjectives | None = None,
    ) -> DaySummary | None:
        non_idle = [a for a in activities if a.activity != ExtendedActivity.IDLE]

        if not non_idle:
            return None

        logger.info(f"Starting summarization with {len(non_idle)} non-idle activities")
        if objectives:
            logger.info(f"Using objectives: main='{objectives.main_objective}'")
            secondary = (
                "\n".join(objectives.secondary_objectives)
                if objectives.secondary_objectives
                else "None"
            )
            logger.info(f"Secondary objectives: {secondary}")

        # Build condensed summary with grouped activities
        condensed = build_condensed_summary(entries=activities)

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

        # Build the final prompt based on whether objectives are provided
        if objectives:
            prompt = DAY_SUMMARIZATION_WITH_OBJECTIVES_PROMPT.format(
                main_objective=objectives.main_objective,
                secondary_objectives_section=self._format_objectives_section(objectives),
                percentage_breakdown=percentage_text,
                activities_text=activities_text,
            )
        else:
            prompt = DAY_SUMMARIZATION_PROMPT.format(
                percentage_breakdown=percentage_text,
                activities_text=activities_text,
            )
        logger.debug(f"Day summarization prompt:\n{prompt}")

        try:
            response_text = self.provider.generate(prompt, temperature=0.7)
        except Exception as e:
            logger.error(f"Failed to summarize day activities: {e}", exc_info=True)
            return None

        start_time = datetime.fromisoformat(non_idle[0].timestamp)
        end_time = datetime.fromisoformat(non_idle[-1].timestamp)

        logger.debug(f"Day summary generated for {start_time.date()}")
        return DaySummary(
            summary=response_text,
            percentages_breakdown=percentage_text,
            start_time=start_time,
            end_time=end_time,
        )
