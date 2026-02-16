import Foundation
import GRDB

/// Database helper for CLI commands (simpler than TCA DatabaseClient)
final class DatabaseHelper: @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    init() throws {
        let dbPath = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/zeit/zeit.db")

        // Ensure the parent directory exists
        let dir = dbPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        self.dbQueue = try DatabaseQueue(path: dbPath.path)
        try DatabaseHelper.createTablesIfNeeded(dbQueue)
    }

    /// Initialize with explicit path (for testing)
    init(path: String) throws {
        self.dbQueue = try DatabaseQueue(path: path)
    }

    private static func createTablesIfNeeded(_ dbQueue: DatabaseQueue) throws {
        try dbQueue.write { db in
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
        try ensureDefaultActivityTypes(dbQueue)
    }

    private static func ensureDefaultActivityTypes(_ dbQueue: DatabaseQueue) throws {
        let count: Int = try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM activity_types") ?? 0
        }

        if count == 0 {
            let now = ISO8601DateFormatter().string(from: Date())
            try dbQueue.write { db in
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
        try await dbQueue.read { db in
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
        let now = ISO8601DateFormatter().string(from: Date())

        try await dbQueue.write { db in
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

    // MARK: - Activities

    func getDayRecord(date: String) async throws -> DayRecord? {
        try await dbQueue.read { db in
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
        try await dbQueue.read { db in
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

    func insertActivity(_ entry: ActivityEntry) async throws {
        let today = DateHelpers.todayString()
        let now = ISO8601DateFormatter().string(from: Date())

        try await dbQueue.write { db in
            // Check if record exists for today
            if let row = try Row.fetchOne(
                db,
                sql: "SELECT activities FROM daily_activities WHERE date = ?",
                arguments: [today]
            ) {
                // Append to existing activities
                let activitiesJson: String = row["activities"]
                var activities = (try? self.parseActivities(from: activitiesJson)) ?? []
                activities.append(entry)

                let newJson = try self.encodeActivities(activities)

                try db.execute(
                    sql: """
                        UPDATE daily_activities
                        SET activities = ?, updated_at = ?
                        WHERE date = ?
                        """,
                    arguments: [newJson, now, today]
                )
            } else {
                // Create new record
                let json = try self.encodeActivities([entry])

                try db.execute(
                    sql: """
                        INSERT INTO daily_activities (date, activities, created_at, updated_at)
                        VALUES (?, ?, ?, ?)
                        """,
                    arguments: [today, json, now, now]
                )
            }
        }
    }

    func deleteDayRecord(date: String) async throws -> Bool {
        try await dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM daily_activities WHERE date = ?",
                arguments: [date]
            )
            return db.changesCount > 0
        }
    }

    // MARK: - Objectives

    func getDayObjectives(date: String) async throws -> DayObjectives? {
        try await dbQueue.read { db in
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
        let now = ISO8601DateFormatter().string(from: Date())
        let secondaryJson = try JSONEncoder().encode(Array(secondary.prefix(2)))
        let secondaryString = String(data: secondaryJson, encoding: .utf8) ?? "[]"

        try await dbQueue.write { db in
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
        try await dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM day_objectives WHERE date = ?",
                arguments: [date]
            )
            return db.changesCount > 0
        }
    }

    // MARK: - Parsing

    private func parseActivities(from json: String) throws -> [ActivityEntry] {
        guard let data = json.data(using: .utf8) else {
            return []
        }
        return try JSONDecoder().decode([ActivityEntry].self, from: data)
    }

    private func encodeActivities(_ activities: [ActivityEntry]) throws -> String {
        let data = try JSONEncoder().encode(activities)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private func parseSecondaryObjectives(from json: String) -> [String] {
        guard let data = json.data(using: .utf8),
            let array = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return array
    }
}

// MARK: - Errors

enum DatabaseHelperError: LocalizedError {
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let path):
            return "Database not found at \(path)"
        }
    }
}
