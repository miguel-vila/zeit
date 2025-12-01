#!/usr/bin/env python3
"""Simple script to view activity data from the database."""

import sys
from datetime import datetime, timedelta
from activity_summarization import compute_summary
from db import DatabaseManager

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
    """View activities for today."""
    today = datetime.now().strftime("%Y-%m-%d")
    view_day(db, today)

def view_yesterday(db: DatabaseManager):
    """View activities for yesterday."""
    yesterday = (datetime.now() - timedelta(days=1)).strftime("%Y-%m-%d")
    view_day(db, yesterday)

def main():
    if len(sys.argv) > 1:
        command = sys.argv[1]

        with DatabaseManager() as db:
            if command == "today":
                view_today(db)
            elif command == "yesterday":
                view_yesterday(db)
            elif command == "all":
                view_all_days(db)
            else:
                # Assume it's a date in YYYY-MM-DD format
                view_day(db, command)
    else:
        # Default: show today
        with DatabaseManager() as db:
            view_today(db)

if __name__ == "__main__":
    main()
