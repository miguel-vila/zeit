from datetime import datetime, timedelta

DATE_FORMAT = "%Y-%m-%d"


def today_str() -> str:
    """Return today's date as YYYY-MM-DD string."""
    return datetime.now().strftime(DATE_FORMAT)


def yesterday_str() -> str:
    """Return yesterday's date as YYYY-MM-DD string."""
    return (datetime.now() - timedelta(days=1)).strftime(DATE_FORMAT)


def format_date(dt: datetime) -> str:
    """Format a datetime object as YYYY-MM-DD string."""
    return dt.strftime(DATE_FORMAT)
