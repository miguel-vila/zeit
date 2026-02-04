#!/usr/bin/env python3

from datetime import datetime

import typer
from rich import print as rprint
from rich.table import Table

from zeit.core.config import get_config
from zeit.core.llm_provider import LLMProvider, OllamaProvider, OpenAIProvider
from zeit.core.logging_config import setup_logging
from zeit.core.utils import today_str, yesterday_str
from zeit.data.db import DatabaseManager
from zeit.processing.activity_stats import compute_activity_breakdown, get_day_stats
from zeit.processing.day_summarizer import DaySummarizer

setup_logging()

# CLI formatting constants
SEPARATOR_WIDTH = 70
SEPARATOR_DOUBLE = "=" * SEPARATOR_WIDTH
SEPARATOR_SINGLE = "-" * SEPARATOR_WIDTH


def print_header(title: str) -> None:
    """Print a header with double-line separators."""
    print(f"\n{SEPARATOR_DOUBLE}")
    print(title)
    print(SEPARATOR_DOUBLE)


def print_footer() -> None:
    """Print a footer separator."""
    print(f"{SEPARATOR_DOUBLE}\n")


def print_section_divider() -> None:
    """Print a single-line section divider."""
    print(SEPARATOR_SINGLE)


app = typer.Typer(
    name="view_data",
    help="View and summarize Zeit activity data",
    add_completion=False,
)


def _print_day_activities(date_str: str) -> None:
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

        summary = compute_activity_breakdown(day_record.activities, include_idle=False)

        print(SEPARATOR_DOUBLE)
        print("Daily Summary:")
        print_section_divider()
        for stat in summary:
            print(f"- {stat.activity}: {stat.percentage:.2f}%")
        print_footer()


def _print_all_days() -> None:
    with DatabaseManager() as db:
        cursor = db.conn.cursor()
        cursor.execute(
            "SELECT date, activities, created_at FROM daily_activities ORDER BY date DESC"
        )
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


def _parse_model_override(override: str) -> tuple[str, str]:
    """Parse model override in format 'provider:model'.

    Returns:
        Tuple of (provider, model)

    Raises:
        ValueError: If format is invalid
    """
    if ":" not in override:
        raise ValueError(
            f"Invalid format '{override}'. Expected 'provider:model' (e.g., 'openai:gpt-4o-mini')"
        )

    provider, _, model = override.partition(":")
    if provider not in ("ollama", "openai"):
        raise ValueError(f"Unknown provider '{provider}'. Supported: ollama, openai")
    if not model:
        raise ValueError("Model name cannot be empty")
    return provider, model


def _summarize_day_impl(date_str: str, model_override: str | None = None) -> None:
    with DatabaseManager() as db:
        day_record = db.get_day_record(date_str)

        if day_record is None:
            print(f"No activities recorded for {date_str}")
            return

        # Fetch objectives for this day (if any)
        objectives = db.get_day_objectives(date_str)

        config = get_config()
        text_config = config.models.text

        # Determine provider and model (override takes precedence)
        if model_override:
            provider_name, model_name = _parse_model_override(model_override)
        else:
            provider_name = text_config.provider
            model_name = text_config.model

        # Create provider
        provider: LLMProvider
        if provider_name == "openai":
            provider = OpenAIProvider(model=model_name)
        else:
            provider = OllamaProvider(model=model_name)

        summarizer = DaySummarizer(provider)
        result = summarizer.summarize(day_record.activities, objectives=objectives)

        if result is None:
            print(f"No non-idle activities recorded for {date_str}")
            return

        print_header(f"Day Summary for {date_str}")
        print(f"({result.start_time.strftime('%H:%M')} - {result.end_time.strftime('%H:%M')})")
        if objectives:
            print(f"Main objective: {objectives.main_objective}")
            if objectives.secondary_objectives:
                print(f"Secondary: {', '.join(objectives.secondary_objectives)}")
        print()
        print(result.summary)
        print()
        print("**Percentages Breakdown:**")
        print()
        print(result.percentages_breakdown)
        print_footer()


@app.command("today")
def cmd_today() -> None:
    _print_day_activities(today_str())


@app.command("yesterday")
def cmd_yesterday() -> None:
    _print_day_activities(yesterday_str())


@app.command("all")
def cmd_all() -> None:
    _print_all_days()


@app.command("day")
def cmd_day(date: str = typer.Argument(..., help="Date in YYYY-MM-DD format")) -> None:
    _print_day_activities(date)


@app.command("summarize")
def cmd_summarize(
    date: str | None = typer.Argument(None, help="Date in YYYY-MM-DD format (defaults to today)"),
    model: str | None = typer.Option(
        None,
        "--model",
        "-m",
        help="Override model in format 'provider:model' (e.g., 'openai:gpt-4o-mini')",
    ),
) -> None:
    """Generate an AI summary of activities for a day."""
    date_str = date if date else today_str()
    try:
        _summarize_day_impl(date_str, model_override=model)
    except ValueError as e:
        print(f"Error: {e}")
        raise typer.Exit(1) from e


@app.command("objectives")
def cmd_objectives(
    date: str | None = typer.Argument(None, help="Date in YYYY-MM-DD format (defaults to today)"),
) -> None:
    """View objectives for a specific day."""
    date_str = date if date else today_str()

    with DatabaseManager() as db:
        objectives = db.get_day_objectives(date_str)

        if objectives is None:
            print(f"No objectives set for {date_str}")
            return

        print_header(f"Objectives for {date_str}")
        print(f"Main: {objectives.main_objective}")
        if objectives.secondary_objectives:
            print("\nSecondary:")
            for obj in objectives.secondary_objectives:
                print(f"  - {obj}")
        print_footer()


@app.command("delete-objectives")
def cmd_delete_objectives(
    date: str = typer.Argument(..., help="Date in YYYY-MM-DD format"),
) -> None:
    """Delete objectives for a specific day."""
    with DatabaseManager() as db:
        deleted = db.delete_day_objectives(date)

        if deleted:
            print(f"Deleted objectives for {date}")
        else:
            print(f"No objectives found for {date}")


@app.command("set-objectives")
def cmd_set_objectives(
    main: str = typer.Option(..., "--main", help="Main objective for the day"),
    opt1: str | None = typer.Option(None, "--opt1", help="First secondary objective"),
    opt2: str | None = typer.Option(None, "--opt2", help="Second secondary objective"),
    date: str | None = typer.Option(
        None, "--date", help="Date in YYYY-MM-DD format (defaults to today)"
    ),
) -> None:
    """Set objectives for a specific day."""
    date_str = date if date else today_str()

    secondary = [obj for obj in [opt1, opt2] if obj is not None]

    with DatabaseManager() as db:
        success = db.save_day_objectives(date_str, main, secondary)

        if success:
            print(f"Objectives set for {date_str}")
            print(f"Main: {main}")
            if secondary:
                print(f"Secondary: {', '.join(secondary)}")
        else:
            print(f"Failed to set objectives for {date_str}")


# Category colors for rich output
CATEGORY_COLORS = {
    "work": "blue",
    "personal": "magenta",
    "system": "dim",
}


def cmd_stats(
    date: str | None = None,
    json_output: bool = False,
    include_idle: bool = False,
) -> None:
    """Show activity statistics for a day.

    This is the implementation used by `zeit stats` command.
    """
    import json

    date_str = date if date else today_str()
    stats = get_day_stats(date_str)

    if stats is None:
        rprint(f"[yellow]No data found for {date_str}[/yellow]")
        raise typer.Exit(1)

    # Filter out idle activities unless --include-idle is set
    if include_idle:
        activities_to_show = stats.activities
        total_for_percentage = stats.total_samples
    else:
        activities_to_show = [a for a in stats.activities if a.activity != "idle"]
        total_for_percentage = stats.total_samples - stats.idle_count

    if json_output:
        if include_idle:
            print(json.dumps(stats.model_dump(), indent=2))
        else:
            # Recalculate percentages for non-idle activities
            filtered_stats = stats.model_dump()
            filtered_stats["activities"] = [
                {
                    **a,
                    "percentage": (a["count"] / total_for_percentage * 100)
                    if total_for_percentage > 0
                    else 0,
                }
                for a in filtered_stats["activities"]
                if a["activity"] != "idle"
            ]
            filtered_stats["total_samples"] = total_for_percentage
            print(json.dumps(filtered_stats, indent=2))
        return

    # Header
    rprint(f"\n[bold]Activity Statistics for {date_str}[/bold]")
    if include_idle:
        rprint(f"Total samples: {stats.total_samples}\n")
    else:
        rprint(f"Total samples: {total_for_percentage} (excluding {stats.idle_count} idle)\n")

    # Summary cards
    if include_idle:
        rprint(
            f"[blue]Work: {stats.work_percentage:.1f}%[/blue] | "
            f"[magenta]Personal: {stats.personal_percentage:.1f}%[/magenta] | "
            f"[dim]Idle: {stats.idle_percentage:.1f}%[/dim]\n"
        )
    else:
        # Recalculate work/personal percentages excluding idle
        if total_for_percentage > 0:
            work_pct = (stats.work_count / total_for_percentage) * 100
            personal_pct = (stats.personal_count / total_for_percentage) * 100
        else:
            work_pct = 0.0
            personal_pct = 0.0
        rprint(
            f"[blue]Work: {work_pct:.1f}%[/blue] | "
            f"[magenta]Personal: {personal_pct:.1f}%[/magenta]\n"
        )

    # Detailed table
    table = Table(title="Activity Breakdown")
    table.add_column("Activity", style="cyan")
    table.add_column("Category", style="dim")
    table.add_column("Count", justify="right")
    table.add_column("Percentage", justify="right")
    table.add_column("Bar", style="green")

    for activity_stat in activities_to_show:
        # Recalculate percentage if excluding idle
        if include_idle or total_for_percentage == 0:
            percentage = activity_stat.percentage
        else:
            percentage = (activity_stat.count / total_for_percentage) * 100

        # Create a simple bar
        bar_width = int(percentage / 2)  # Max 50 chars for 100%
        bar = "█" * bar_width

        category_color = CATEGORY_COLORS.get(activity_stat.category, "white")
        category_display = f"[{category_color}]{activity_stat.category}[/{category_color}]"

        table.add_row(
            activity_stat.activity.replace("_", " ").title(),
            category_display,
            str(activity_stat.count),
            f"{percentage:.1f}%",
            bar,
        )

    rprint(table)


if __name__ == "__main__":
    app()
