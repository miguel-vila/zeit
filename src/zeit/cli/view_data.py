#!/usr/bin/env python3

from datetime import datetime, timedelta

from ollama import Client
from zeit.core.config import get_config
from zeit.core.utils import today_str
from zeit.processing.activity_summarization import compute_summary
from zeit.processing.day_summarizer import DaySummarizer
from zeit.data.db import DatabaseManager

def view_day(db: DatabaseManager, date_str: str):
    """View activities for a specific day."""
    day_record = db.get_day_record(date_str)

    if day_record is None:
        print(f"No data found for {date_str}")
        return

    print(f"\n{'='*70}")
    print(f"Activities for {date_str}")
    print(f"{'='*70}")
    print(f"Total activities: {len(day_record.activities)}\n")

    for i, activity in enumerate(day_record.activities, 1):
        timestamp = datetime.fromisoformat(activity.timestamp)
        time_str = timestamp.strftime("%H:%M:%S")
        print(f"{i}. [{time_str}] {activity.activity.value}")
        if activity.reasoning:
            print(f"   Reasoning: {activity.reasoning}")
        print()
        
    summary = compute_summary(day_record.activities)
    
    print(f"{'='*70}")
    print("Daily Summary:")
    print(f"{'-'*70}")
    for summary_entry in summary:
        print(f"- {summary_entry.activity.value}: {summary_entry.percentage:.2f}%")
    print(f"{'='*70}\n")
    

def view_all_days(db: DatabaseManager):
    """View summary of all days in the database."""
    cursor = db.conn.cursor()
    cursor.execute("SELECT date, activities, created_at FROM daily_activities ORDER BY date DESC")
    rows = cursor.fetchall()

    if not rows:
        print("No data in database yet.")
        return

    print(f"\n{'='*70}")
    print(f"All Days Summary")
    print(f"{'='*70}\n")

    for row in rows:
        date = row["date"]
        day_record = db.get_day_record(date)
        if day_record:
            print(f"{date}: {len(day_record.activities)} activities")

            # Show activity breakdown
            activity_counts = {}
            for activity in day_record.activities:
                activity_name = activity.activity.value
                activity_counts[activity_name] = activity_counts.get(activity_name, 0) + 1

            for activity_name, count in sorted(activity_counts.items(), key=lambda x: -x[1]):
                print(f"  - {activity_name}: {count}")
            print()

def view_today(db: DatabaseManager):
    view_day(db, today_str())

def view_yesterday(db: DatabaseManager):
    """View activities for yesterday."""
    yesterday = (datetime.now() - timedelta(days=1)).strftime("%Y-%m-%d")
    view_day(db, yesterday)


def summarize_day(db: DatabaseManager, date_str: str):
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

    print(f"\n{'='*70}")
    print(f"Day Summary for {date_str}")
    print(f"({result.start_time.strftime('%H:%M')} - {result.end_time.strftime('%H:%M')})")
    print(f"{'='*70}\n")
    print(result.summary)
    print(f"\n{'='*70}\n")
