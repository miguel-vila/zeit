import Foundation
import GRDB

/// Schema definition shared by the GUI's `DatabaseClient` and the CLI's
/// `DatabaseHelper`, so the two paths cannot disagree about the schema.
///
/// The first migration is a baseline that recreates the tables exactly as the
/// pre-migrator `CREATE TABLE IF NOT EXISTS` code did, which makes it a no-op on
/// databases that already exist. Every schema change after that is a migration.
enum ZeitDatabase {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("baseline") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS daily_activities (
                    date TEXT PRIMARY KEY,
                    activities TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS day_objectives (
                    date TEXT PRIMARY KEY,
                    main_objective TEXT NOT NULL,
                    secondary_objectives TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS activity_types (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    description TEXT NOT NULL,
                    is_work INTEGER NOT NULL,
                    sort_order INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                """)
        }

        // Replace the work/personal boolean on an activity type with a group.
        //
        // Only ids Zeit itself shipped are remapped by name: guessing a group for a
        // user-written type would write wrong knowledge into a migration. No id is
        // renamed, because entries reference ids.
        migrator.registerMigration("activity-group") { db in
            try db.execute(sql: """
                CREATE TABLE activity_types_new (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    description TEXT NOT NULL,
                    activity_group TEXT NOT NULL,
                    sort_order INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                """)
            try db.execute(sql: """
                INSERT INTO activity_types_new
                    (id, name, description, activity_group, sort_order, created_at, updated_at)
                SELECT
                    id,
                    name,
                    description,
                    CASE
                        WHEN is_work = 1 THEN 'work'
                        WHEN id IN ('professional_development', 'personal_ai_use')
                            THEN 'personal_projects'
                        ELSE 'personal'
                    END,
                    sort_order,
                    created_at,
                    updated_at
                FROM activity_types
                """)
            try db.execute(sql: "DROP TABLE activity_types")
            try db.execute(sql: "ALTER TABLE activity_types_new RENAME TO activity_types")
        }

        return migrator
    }

    /// Bring a database up to the current schema and seed the starter activity
    /// types when the table is empty.
    static func prepare(_ dbQueue: DatabaseQueue) throws {
        try migrator.migrate(dbQueue)
        try seedDefaultActivityTypes(dbQueue)
    }

    /// Write the starter set when no activity types exist.
    ///
    /// This runs for the machine where nobody opens the GUI. It deliberately does
    /// not read `conf.yml`: the database layer must not depend on config to decide
    /// what to insert.
    static func seedDefaultActivityTypes(_ dbQueue: DatabaseQueue) throws {
        let count: Int = try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM activity_types") ?? 0
        }
        guard count == 0 else { return }

        try dbQueue.write { db in
            try insertActivityTypes(ActivityCatalog.starterSet, into: db)
        }
    }

    /// Make `activity_types` hold exactly `types`, keeping the rows it already
    /// has.
    ///
    /// The editor's list is the whole catalog, so a save both updates and
    /// prunes. A type the user kept is updated in place and kept as the same
    /// row: `created_at` still says when it first appeared, and a save that
    /// changes one type cannot disturb the others. A type absent from the list
    /// was removed in the editor, which is the only way a type leaves the
    /// catalog, so its row goes.
    ///
    /// Writing the table as a delete and a reinsert did all of this by
    /// coincidence and lost `created_at` every time, so a save that should have
    /// edited one description rewrote the whole catalog.
    static func saveActivityTypes(_ types: [ActivityType], into db: Database) throws {
        let now = ISO8601DateFormatter().string(from: Date())

        for (index, type) in types.enumerated() {
            try db.execute(
                sql: """
                    INSERT INTO activity_types
                    (id, name, description, activity_group, sort_order, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        name = excluded.name,
                        description = excluded.description,
                        activity_group = excluded.activity_group,
                        sort_order = excluded.sort_order,
                        updated_at = excluded.updated_at
                    """,
                arguments: [
                    type.id, type.name, type.description,
                    type.group.rawValue, index, now, now,
                ]
            )
        }

        // An empty list needs its own statement: `NOT IN ()` is not SQL.
        if types.isEmpty {
            try db.execute(sql: "DELETE FROM activity_types")
        } else {
            let placeholders = databaseQuestionMarks(count: types.count)
            try db.execute(
                sql: "DELETE FROM activity_types WHERE id NOT IN (\(placeholders))",
                arguments: StatementArguments(types.map(\.id))
            )
        }
    }

    /// Insert activity types, assigning `sort_order` from the list order.
    static func insertActivityTypes(_ types: [ActivityType], into db: Database) throws {
        let now = ISO8601DateFormatter().string(from: Date())

        for (index, type) in types.enumerated() {
            try db.execute(
                sql: """
                    INSERT INTO activity_types
                    (id, name, description, activity_group, sort_order, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    type.id, type.name, type.description,
                    type.group.rawValue, index, now, now,
                ]
            )
        }
    }

    /// Read all activity types in display order.
    static func fetchActivityTypes(_ db: Database) throws -> [ActivityType] {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT id, name, description, activity_group
                FROM activity_types
                ORDER BY sort_order, id
                """
        )

        return rows.map { row in
            ActivityType(
                id: row["id"],
                name: row["name"],
                description: row["description"],
                group: ActivityGroup(rawValue: row["activity_group"]) ?? .personal
            )
        }
    }
}
