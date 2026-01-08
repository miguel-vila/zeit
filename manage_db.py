#!/usr/bin/env python3
"""Database management CLI for Zeit activity tracker."""

import typer
from datetime import datetime
from typing import Optional
from rich import print as rprint
from rich.prompt import Confirm
from pathlib import Path

from zeit.data.db import DatabaseManager
from zeit.core.utils import today_str

app = typer.Typer(
    name="manage_db",
    help="Database management tool for Zeit activity tracker",
    add_completion=False,
)


@app.command("delete-today")
def delete_today(
    force: bool = typer.Option(
        False,
        "--force",
        "-f",
        help="Skip confirmation prompt"
    )
):
    """
    Delete all activity entries for today.

    This command removes all activities recorded for the current date
    from the database. Use with caution as this operation cannot be undone.
    """
    today = today_str()

    with DatabaseManager() as db:
        # Get current day record to show what will be deleted
        day_record = db.get_day_record(today)

        if day_record is None or len(day_record.activities) == 0:
            rprint(f"[yellow]No activities found for {today}[/yellow]")
            return

        # Show what will be deleted
        activity_count = len(day_record.activities)
        rprint(f"\n[bold]Found {activity_count} activities for {today}[/bold]")

        # Confirm deletion unless --force is used
        if not force:
            confirmed = Confirm.ask(
                f"[red]Are you sure you want to delete all {activity_count} activities?[/red]"
            )
            if not confirmed:
                rprint("[yellow]Deletion cancelled[/yellow]")
                raise typer.Abort()

        # Delete the day record
        success = db.delete_day_record(today)

        if success:
            rprint(f"[green]✓[/green] Successfully deleted {activity_count} activities for {today}")
        else:
            rprint(f"[red]✗[/red] Failed to delete activities for {today}")
            raise typer.Exit(code=1)


@app.command("info")
def database_info():
    """
    Display information about the database.

    Shows the database location and basic statistics.
    """
    db_path = Path("data/zeit.db")

    if not db_path.exists():
        rprint("[red]Database file not found at data/zeit.db[/red]")
        raise typer.Exit(code=1)

    file_size = db_path.stat().st_size
    file_size_kb = file_size / 1024

    rprint(f"\n[bold]Database Information[/bold]")
    rprint(f"Location: {db_path.absolute()}")
    rprint(f"Size: {file_size_kb:.2f} KB ({file_size} bytes)")

    with DatabaseManager() as db:
        all_days = db.get_all_days()
        total_days = len(all_days)
        total_activities = sum(count for _, count in all_days)

        rprint(f"Total days with data: {total_days}")
        rprint(f"Total activities: {total_activities}")

        if total_days > 0:
            avg_activities = total_activities / total_days
            rprint(f"Average activities per day: {avg_activities:.1f}")


if __name__ == "__main__":
    app()
