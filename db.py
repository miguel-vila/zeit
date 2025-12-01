import sqlite3
import json
import logging
from datetime import datetime
from pathlib import Path
from typing import List, Optional
from pydantic import BaseModel, Field
from activity_id import ActivitiesResponseWithTimestamp, ExtendedActivity

logger = logging.getLogger(__name__)

class ActivityEntry(BaseModel):
    """Represents a single activity at a specific time."""
    timestamp: str = Field(description="ISO format timestamp when the activity was detected")
    activity: ExtendedActivity = Field(description="The detected activity type")
    reasoning: Optional[str] = Field(default=None, description="Reasoning for why this activity was identified")

    @classmethod
    def from_response(cls, activities_response: ActivitiesResponseWithTimestamp):
        """Create an ActivityEntry from an ActivitiesResponse."""
        return cls(
            timestamp=activities_response.timestamp.isoformat(),
            activity=ExtendedActivity(activities_response.main_activity.value),
            reasoning=activities_response.reasoning
        )

    @classmethod
    def idle(cls, timestamp: datetime):
        """Create an ActivityEntry for idle state."""
        return cls(
            timestamp=timestamp.isoformat(),
            activity=ExtendedActivity.IDLE,
            reasoning=None
        )

class DayRecord(BaseModel):
    """Represents all activities for a single day."""
    date: str = Field(description="Date in YYYY-MM-DD format")
    activities: List[ActivityEntry] = Field(description="List of activities detected during the day")

    def add_activity(self, entry: ActivityEntry):
        """Add an activity entry to this day."""
        self.activities.append(entry)

    def to_json(self) -> str:
        """Convert activities list to JSON string for database storage."""
        return json.dumps([activity.model_dump() for activity in self.activities])

    @classmethod
    def from_db_row(cls, date: str, activities_json: str):
        """Create a DayRecord from database row."""
        activities_data = json.loads(activities_json)
        activities = [ActivityEntry(**activity) for activity in activities_data]
        return cls(date=date, activities=activities)

class DatabaseManager:
    """Manages the SQLite database for activity tracking."""

    def __init__(self, db_path: Optional[Path] = None):
        """
        Initialize the database manager.

        Args:
            db_path: Path to the SQLite database file. If None, uses default location.
        """
        if db_path is None:
            db_dir = Path("data")
            db_dir.mkdir(parents=True, exist_ok=True)
            db_path = db_dir / "zeit.db"

        self.db_path = db_path
        # self.conn: Optional[sqlite3.Connection] = None
        logger.info(f"Initializing database at {self.db_path}")
        self._connect()
        self._create_tables()

    def _connect(self):
        """Establish connection to the database."""
        try:
            self.conn = sqlite3.connect(str(self.db_path))
            self.conn.row_factory = sqlite3.Row
            logger.debug("Database connection established")
        except sqlite3.Error as e:
            logger.error(f"Failed to connect to database: {e}", exc_info=True)
            raise

    def _create_tables(self):
        """Create the necessary tables if they don't exist."""
        try:
            cursor = self.conn.cursor()
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS daily_activities (
                    date TEXT PRIMARY KEY,
                    activities TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
            """)
            self.conn.commit()
            logger.debug("Tables created/verified successfully")
        except sqlite3.Error as e:
            logger.error(f"Failed to create tables: {e}", exc_info=True)
            raise

    def insert_activity(self, activity_entry: ActivityEntry) -> bool:
        """
        Atomically insert a new activity for a particular day.

        If the day already exists, appends to the activities list.
        If the day doesn't exist, creates a new record.

        Args:
            activity_entry: The activity entry to insert

        Returns:
            True if successful, False otherwise
        """
        try:
            # Extract date from timestamp
            timestamp = datetime.fromisoformat(activity_entry.timestamp)
            date_str = timestamp.strftime("%Y-%m-%d")
            now = datetime.now().isoformat()

            # Start transaction
            cursor = self.conn.cursor()

            # Check if record exists for this day
            cursor.execute("SELECT activities FROM daily_activities WHERE date = ?", (date_str,))
            row = cursor.fetchone()

            if row:
                # Day exists - append to existing activities
                day_record = DayRecord.from_db_row(date_str, row["activities"])
                day_record.add_activity(activity_entry)

                cursor.execute(
                    "UPDATE daily_activities SET activities = ?, updated_at = ? WHERE date = ?",
                    (day_record.to_json(), now, date_str)
                )
                logger.debug(f"Updated existing day record for {date_str}")
            else:
                # Day doesn't exist - create new record
                day_record = DayRecord(date=date_str, activities=[])
                day_record.add_activity(activity_entry)

                cursor.execute(
                    "INSERT INTO daily_activities (date, activities, created_at, updated_at) VALUES (?, ?, ?, ?)",
                    (date_str, day_record.to_json(), now, now)
                )
                logger.debug(f"Created new day record for {date_str}")

            # Commit transaction
            self.conn.commit()
            logger.info(f"Successfully inserted activity '{activity_entry.activity.value}' for {date_str}")
            return True

        except sqlite3.Error as e:
            logger.error(f"Database error while inserting activity: {e}", exc_info=True)
            self.conn.rollback()
            return False
        except Exception as e:
            logger.error(f"Unexpected error while inserting activity: {e}", exc_info=True)
            self.conn.rollback()
            return False

    def get_day_record(self, date_str: str) -> Optional[DayRecord]:
        """
        Retrieve all activities for a specific day.

        Args:
            date_str: Date in YYYY-MM-DD format

        Returns:
            DayRecord if found, None otherwise
        """
        try:
            cursor = self.conn.cursor()
            cursor.execute("SELECT date, activities FROM daily_activities WHERE date = ?", (date_str,))
            row = cursor.fetchone()

            if row:
                return DayRecord.from_db_row(row["date"], row["activities"])
            return None
        except sqlite3.Error as e:
            logger.error(f"Failed to retrieve day record for {date_str}: {e}", exc_info=True)
            return None

    def close(self):
        """Close the database connection."""
        if self.conn:
            self.conn.close()
            logger.debug("Database connection closed")

    def __enter__(self):
        """Context manager entry."""
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit."""
        self.close()
