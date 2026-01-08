#!/usr/bin/env python3

from datetime import datetime
from typing import Optional

import typer
from ollama import Client

from zeit.core.config import get_config
from zeit.core.utils import today_str, yesterday_str
from zeit.processing.activity_summarization import compute_summary
from zeit.processing.day_summarizer import DaySummarizer
from zeit.data.db import DatabaseManager

# CLI formatting constants
SEPARATOR_WIDTH = 70
SEPARATOR_DOUBLE = "=" * SEPARATOR_WIDTH
SEPARATOR_SINGLE = "-" * SEPARATOR_WIDTH


def print_header(title: str):
    """Print a header with double-line separators."""
    print(f"\n{SEPARATOR_DOUBLE}")
    print(title)
    print(SEPARATOR_DOUBLE)


def print_footer():
    """Print a footer separator."""
    print(f"{SEPARATOR_DOUBLE}\n")


def print_section_divider():
    """Print a single-line section divider."""
    print(SEPARATOR_SINGLE)


app = typer.Typer(
    name="view_data",
    help="View and summarize Zeit activity data",
    add_completion=False,
)


def _print_day_activities(date_str: str):
    with DatabaseManager() as db:
        day_record = db.get_day_record(date_str)

        if day_record is None:
            print(f"No data found for {date_str}")
            return

        print_header(f"Activities for {date_str}")
        print(f"Total activities: {len(day_record.activities)}\n")

        for i, activity in enumerate(day_record.activities, 1):
            timestamp = datetime.fromisoformat(activity.timestamp)
            time_str = timestamp.strftime("%H:%M:%S")
            print(f"{i}. [{time_str}] {activity.activity.value}")
            if activity.reasoning:
                print(f"   Reasoning: {activity.reasoning}")
            print()

        summary = compute_summary(day_record.activities)

        print(SEPARATOR_DOUBLE)
        print("Daily Summary:")
        print_section_divider()
        for summary_entry in summary:
            print(f"- {summary_entry.activity.value}: {summary_entry.percentage:.2f}%")
        print_footer()


def _print_all_days():
    with DatabaseManager() as db:
        cursor = db.conn.cursor()
        cursor.execute("SELECT date, activities, created_at FROM daily_activities ORDER BY date DESC")
        rows = cursor.fetchall()

        if not rows:
            print("No data in database yet.")
            return

        print_header("All Days Summary")
        print()  # Extra line after header

        for row in rows:
            date = row["date"]
            day_record = db.get_day_record(date)
            if day_record:
                print(f"{date}: {len(day_record.activities)} activities")

                activity_counts: dict[str, int] = {}
                for activity in day_record.activities:
                    activity_name = activity.activity.value
                    activity_counts[activity_name] = activity_counts.get(activity_name, 0) + 1

                for activity_name, count in sorted(activity_counts.items(), key=lambda x: -x[1]):
                    print(f"  - {activity_name}: {count}")
                print()


def _summarize_day_impl(date_str: str):
    with DatabaseManager() as db:
        day_record = db.get_day_record(date_str)

        if day_record is None:
            print(f"No activities recorded for {date_str}")
            return

        config = get_config()
        summarizer = DaySummarizer(Client(), llm=config.models.text)
        result = summarizer.summarize(day_record.activities)

        if result is None:
            print(f"No non-idle activities recorded for {date_str}")
            return

        print_header(f"Day Summary for {date_str}")
        print(f"({result.start_time.strftime('%H:%M')} - {result.end_time.strftime('%H:%M')})")
        print()
        print(result.summary)
        print_footer()


@app.command("today")
def cmd_today():
    _print_day_activities(today_str())


@app.command("yesterday")
def cmd_yesterday():
    _print_day_activities(yesterday_str())


@app.command("all")
def cmd_all():
    _print_all_days()


@app.command("day")
def cmd_day(date: str = typer.Argument(..., help="Date in YYYY-MM-DD format")):
    _print_day_activities(date)


@app.command("summarize")
def cmd_summarize(
    date: Optional[str] = typer.Argument(None, help="Date in YYYY-MM-DD format (defaults to today)")
):
    date_str = date if date else today_str()
    _summarize_day_impl(date_str)


if __name__ == "__main__":
    app()
