#!/usr/bin/env python3
"""Database management CLI commands for Zeit."""

from pathlib import Path

import typer
from rich import print as rprint
from rich.prompt import Confirm

from zeit.core.utils import today_str
from zeit.data.db import DatabaseManager

app = typer.Typer(
    name="db",
    help="Database management commands",
    add_completion=False,
)


@app.command("delete-today")
def delete_today(
    force: bool = typer.Option(False, "--force", "-f", help="Skip confirmation prompt"),
) -> None:
    """
    Delete all activity entries for today.

    This command removes all activities recorded for the current date
    from the database. Use with caution as this operation cannot be undone.
    """
    today = today_str()

    with DatabaseManager() as db:
        day_record = db.get_day_record(today)

        if day_record is None or len(day_record.activities) == 0:
            rprint(f"[yellow]No activities found for {today}[/yellow]")
            return

        activity_count = len(day_record.activities)
        rprint(f"\n[bold]Found {activity_count} activities for {today}[/bold]")

        if not force:
            confirmed = Confirm.ask(
                f"[red]Are you sure you want to delete all {activity_count} activities?[/red]"
            )
            if not confirmed:
                rprint("[yellow]Deletion cancelled[/yellow]")
                raise typer.Abort()

        success = db.delete_day_record(today)

        if success:
            rprint(f"[green]✓[/green] Successfully deleted {activity_count} activities for {today}")
        else:
            rprint(f"[red]✗[/red] Failed to delete activities for {today}")
            raise typer.Exit(code=1)


@app.command("delete-day")
def delete_day(
    date: str = typer.Argument(..., help="Date in YYYY-MM-DD format"),
    force: bool = typer.Option(False, "--force", "-f", help="Skip confirmation prompt"),
) -> None:
    """Delete all activity entries for a specific date."""
    with DatabaseManager() as db:
        day_record = db.get_day_record(date)

        if day_record is None or len(day_record.activities) == 0:
            rprint(f"[yellow]No activities found for {date}[/yellow]")
            return

        activity_count = len(day_record.activities)
        rprint(f"\n[bold]Found {activity_count} activities for {date}[/bold]")

        if not force:
            confirmed = Confirm.ask(
                f"[red]Are you sure you want to delete all {activity_count} activities?[/red]"
            )
            if not confirmed:
                rprint("[yellow]Deletion cancelled[/yellow]")
                raise typer.Abort()

        success = db.delete_day_record(date)

        if success:
            rprint(f"[green]✓[/green] Successfully deleted {activity_count} activities for {date}")
        else:
            rprint(f"[red]✗[/red] Failed to delete activities for {date}")
            raise typer.Exit(code=1)


@app.command("delete-objectives")
def delete_objectives(
    date: str = typer.Argument(..., help="Date in YYYY-MM-DD format"),
    force: bool = typer.Option(False, "--force", "-f", help="Skip confirmation prompt"),
) -> None:
    """Delete objectives for a specific date."""
    with DatabaseManager() as db:
        objectives = db.get_day_objectives(date)

        if objectives is None:
            rprint(f"[yellow]No objectives found for {date}[/yellow]")
            return

        rprint(f"\n[bold]Objectives for {date}:[/bold]")
        rprint(f"  Main: {objectives.main_objective}")
        if objectives.secondary_objectives:
            rprint(f"  Secondary: {', '.join(objectives.secondary_objectives)}")

        if not force:
            confirmed = Confirm.ask("[red]Are you sure you want to delete these objectives?[/red]")
            if not confirmed:
                rprint("[yellow]Deletion cancelled[/yellow]")
                raise typer.Abort()

        success = db.delete_day_objectives(date)

        if success:
            rprint(f"[green]✓[/green] Successfully deleted objectives for {date}")
        else:
            rprint(f"[red]✗[/red] Failed to delete objectives for {date}")
            raise typer.Exit(code=1)


@app.command("info")
def database_info() -> None:
    """Display database location and statistics."""
    db_path = Path("data/zeit.db")

    if not db_path.exists():
        rprint("[red]Database file not found at data/zeit.db[/red]")
        raise typer.Exit(code=1)

    file_size = db_path.stat().st_size
    file_size_kb = file_size / 1024

    rprint("\n[bold]Database Information[/bold]")
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
