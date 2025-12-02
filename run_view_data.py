import sys
from dotenv import load_dotenv
from src.zeit.cli.view_data import view_all_days, view_day, view_today, view_yesterday
from src.zeit.data.db import DatabaseManager

def main():
    load_dotenv()  # Load environment variables from .env file if present
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
