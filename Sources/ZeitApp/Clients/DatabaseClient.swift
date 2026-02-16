import Dependencies
import DependenciesMacros
import Foundation
import GRDB

// MARK: - Client Interface

@DependencyClient
struct DatabaseClient: Sendable {
    /// Get activities for a specific date (YYYY-MM-DD format)
    var getDayRecord: @Sendable (_ date: String) async throws -> DayRecord?

    /// Get all days with activity counts, sorted by date descending
    var getAllDays: @Sendable () async throws -> [(date: String, count: Int)]

    /// Get objectives for a specific date
    var getDayObjectives: @Sendable (_ date: String) async throws -> DayObjectives?

    /// Save objectives for a specific date
    var saveDayObjectives: @Sendable (
        _ date: String,
        _ main: String,
        _ secondary: [String]
    ) async throws -> Void

    /// Delete objectives for a specific date
    var deleteDayObjectives: @Sendable (_ date: String) async throws -> Bool

    /// Delete activities for a specific date
    var deleteDayActivities: @Sendable (_ date: String) async throws -> Bool

    /// Get all activity types
    var getActivityTypes: @Sendable () async throws -> [ActivityType]

    /// Save activity types (replaces all existing types)
    var saveActivityTypes: @Sendable (_ types: [ActivityType]) async throws -> Void
}

// MARK: - Dependency Registration

extension DependencyValues {
    var databaseClient: DatabaseClient {
        get { self[DatabaseClient.self] }
        set { self[DatabaseClient.self] = newValue }
    }
}

// MARK: - Live Implementation

extension DatabaseClient: DependencyKey {
    static let liveValue: DatabaseClient = {
        let actor = DatabaseActor()

        return DatabaseClient(
            getDayRecord: { date in
                try await actor.getDayRecord(date: date)
            },
            getAllDays: {
                try await actor.getAllDays()
            },
            getDayObjectives: { date in
                try await actor.getDayObjectives(date: date)
            },
            saveDayObjectives: { date, main, secondary in
                try await actor.saveDayObjectives(date: date, main: main, secondary: secondary)
            },
            deleteDayObjectives: { date in
                try await actor.deleteDayObjectives(date: date)
            },
            deleteDayActivities: { date in
                try await actor.deleteDayActivities(date: date)
            },
            getActivityTypes: {
                try await actor.getActivityTypes()
            },
            saveActivityTypes: { types in
                try await actor.saveActivityTypes(types)
            }
        )
    }()
}

// MARK: - Database Actor

private actor DatabaseActor {
    private var dbQueue: DatabaseQueue?

    private func getDatabase() throws -> DatabaseQueue {
        if let db = dbQueue {
            return db
        }

        let dbPath = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/zeit/zeit.db")

        // Ensure the parent directory exists
        let dir = dbPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let db = try DatabaseQueue(path: dbPath.path)
        try createTablesIfNeeded(db)
        dbQueue = db
        return db
    }

    private func createTablesIfNeeded(_ db: DatabaseQueue) throws {
        try db.write { db in
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

        // Auto-populate defaults if the activity_types table is empty
        try ensureDefaultActivityTypes(db)
    }

    private func ensureDefaultActivityTypes(_ db: DatabaseQueue) throws {
        let count: Int = try db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM activity_types") ?? 0
        }

        if count == 0 {
            let now = ISO8601DateFormatter().string(from: Date())
            try db.write { db in
                for (index, type) in ActivityType.defaultTypes.enumerated() {
                    try db.execute(
                        sql: """
                            INSERT INTO activity_types
                            (id, name, description, is_work, sort_order, created_at, updated_at)
                            VALUES (?, ?, ?, ?, ?, ?, ?)
                            """,
                        arguments: [
                            type.id, type.name, type.description,
                            type.isWork ? 1 : 0, index, now, now,
                        ]
                    )
                }
            }
        }
    }

    // MARK: - Activity Types

    func getActivityTypes() async throws -> [ActivityType] {
        let db = try getDatabase()

        return try await db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT id, name, description, is_work FROM activity_types ORDER BY sort_order, id"
            )

            return rows.map { row in
                ActivityType(
                    id: row["id"],
                    name: row["name"],
                    description: row["description"],
                    isWork: (row["is_work"] as Int) != 0
                )
            }
        }
    }

    func saveActivityTypes(_ types: [ActivityType]) async throws {
        let db = try getDatabase()
        let now = ISO8601DateFormatter().string(from: Date())

        try await db.write { db in
            try db.execute(sql: "DELETE FROM activity_types")

            for (index, type) in types.enumerated() {
                try db.execute(
                    sql: """
                        INSERT INTO activity_types
                        (id, name, description, is_work, sort_order, created_at, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        type.id, type.name, type.description,
                        type.isWork ? 1 : 0, index, now, now,
                    ]
                )
            }
        }
    }

    // MARK: - Day Records

    func getDayRecord(date: String) async throws -> DayRecord? {
        let db = try getDatabase()

        return try await db.read { [self] db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT date, activities FROM daily_activities WHERE date = ?",
                arguments: [date]
            ) else {
                return nil
            }

            let activitiesJson: String = row["activities"]
            let activities = try self.parseActivities(from: activitiesJson)
            return DayRecord(date: date, activities: activities)
        }
    }

    func getAllDays() async throws -> [(date: String, count: Int)] {
        let db = try getDatabase()

        return try await db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT date, activities FROM daily_activities ORDER BY date DESC"
            )

            return rows.compactMap { row -> (String, Int)? in
                let date: String = row["date"]
                let activitiesJson: String = row["activities"]

                guard let data = activitiesJson.data(using: .utf8),
                    let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
                else {
                    return nil
                }

                return (date, array.count)
            }
        }
    }

    func getDayObjectives(date: String) async throws -> DayObjectives? {
        let db = try getDatabase()

        return try await db.read { [self] db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM day_objectives WHERE date = ?",
                arguments: [date]
            ) else {
                return nil
            }

            let secondaryJson: String = row["secondary_objectives"]
            let secondary = self.parseSecondaryObjectives(from: secondaryJson)

            return DayObjectives(
                date: row["date"],
                mainObjective: row["main_objective"],
                secondaryObjectives: secondary,
                createdAt: row["created_at"],
                updatedAt: row["updated_at"]
            )
        }
    }

    func saveDayObjectives(date: String, main: String, secondary: [String]) async throws {
        let db = try getDatabase()
        let now = ISO8601DateFormatter().string(from: Date())
        let secondaryJson = try JSONEncoder().encode(Array(secondary.prefix(2)))
        let secondaryString = String(data: secondaryJson, encoding: .utf8) ?? "[]"

        try await db.write { db in
            // Check if exists
            let exists = try Row.fetchOne(
                db,
                sql: "SELECT date FROM day_objectives WHERE date = ?",
                arguments: [date]
            ) != nil

            if exists {
                try db.execute(
                    sql: """
                        UPDATE day_objectives
                        SET main_objective = ?, secondary_objectives = ?, updated_at = ?
                        WHERE date = ?
                        """,
                    arguments: [main, secondaryString, now, date]
                )
            } else {
                try db.execute(
                    sql: """
                        INSERT INTO day_objectives
                        (date, main_objective, secondary_objectives, created_at, updated_at)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [date, main, secondaryString, now, now]
                )
            }
        }
    }

    func deleteDayObjectives(date: String) async throws -> Bool {
        let db = try getDatabase()

        return try await db.write { db in
            try db.execute(
                sql: "DELETE FROM day_objectives WHERE date = ?",
                arguments: [date]
            )
            return db.changesCount > 0
        }
    }

    func deleteDayActivities(date: String) async throws -> Bool {
        let db = try getDatabase()

        return try await db.write { db in
            try db.execute(
                sql: "DELETE FROM daily_activities WHERE date = ?",
                arguments: [date]
            )
            return db.changesCount > 0
        }
    }

    // MARK: - Parsing Helpers

    nonisolated private func parseActivities(from json: String) throws -> [ActivityEntry] {
        guard let data = json.data(using: .utf8) else {
            return []
        }

        let decoder = JSONDecoder()
        return try decoder.decode([ActivityEntry].self, from: data)
    }

    nonisolated private func parseSecondaryObjectives(from json: String) -> [String] {
        guard let data = json.data(using: .utf8),
            let array = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return array
    }
}

// MARK: - Errors

enum DatabaseError: LocalizedError {
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let path):
            return "Database not found at \(path)"
        }
    }
}
