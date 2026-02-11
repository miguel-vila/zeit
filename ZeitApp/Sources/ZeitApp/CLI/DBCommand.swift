import ArgumentParser
import Foundation

/// Database management commands
struct DBCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "db",
        abstract: "Database management",
        subcommands: [
            DBInfoCommand.self,
            DBDeleteTodayCommand.self,
            DBDeleteDayCommand.self,
            DBDeleteObjectivesCommand.self,
        ]
    )
}

// MARK: - Info

struct DBInfoCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "info",
        abstract: "Show database information"
    )

    func run() async throws {
        let dbPath = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/zeit/zeit.db")

        print("Database Information")
        print("===================")
        print("")
        print("Path: \(dbPath.path)")

        if FileManager.default.fileExists(atPath: dbPath.path) {
            let attrs = try FileManager.default.attributesOfItem(atPath: dbPath.path)
            if let size = attrs[.size] as? Int64 {
                let sizeKB = Double(size) / 1024
                print("Size: \(String(format: "%.1f", sizeKB)) KB")
            }
            if let modified = attrs[.modificationDate] as? Date {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .medium
                print("Modified: \(formatter.string(from: modified))")
            }

            let db = try DatabaseHelper()
            let days = try await db.getAllDays()
            let totalActivities = days.reduce(0) { $0 + $1.count }

            print("")
            print("Statistics:")
            print("  Days tracked: \(days.count)")
            print("  Total activities: \(totalActivities)")
        } else {
            print("Status: Not found")
        }
    }
}

// MARK: - Delete Today

struct DBDeleteTodayCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "delete-today",
        abstract: "Delete today's activities"
    )

    @Flag(name: .long, help: "Skip confirmation prompt")
    var force: Bool = false

    func run() async throws {
        let today = DateHelpers.todayString()

        if !force {
            print("Delete all activities for \(today)? [y/N] ", terminator: "")
            guard let response = readLine(), response.lowercased() == "y" else {
                print("Cancelled")
                return
            }
        }

        let db = try DatabaseHelper()
        let deleted = try await db.deleteDayRecord(date: today)

        if deleted {
            print("Deleted activities for \(today)")
        } else {
            print("No activities found for \(today)")
        }
    }
}

// MARK: - Delete Day

struct DBDeleteDayCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "delete-day",
        abstract: "Delete activities for a specific day"
    )

    @Argument(help: "Date in YYYY-MM-DD format")
    var date: String

    @Flag(name: .long, help: "Skip confirmation prompt")
    var force: Bool = false

    func run() async throws {
        if !force {
            print("Delete all activities for \(date)? [y/N] ", terminator: "")
            guard let response = readLine(), response.lowercased() == "y" else {
                print("Cancelled")
                return
            }
        }

        let db = try DatabaseHelper()
        let deleted = try await db.deleteDayRecord(date: date)

        if deleted {
            print("Deleted activities for \(date)")
        } else {
            print("No activities found for \(date)")
        }
    }
}

// MARK: - Delete Objectives

struct DBDeleteObjectivesCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "delete-objectives",
        abstract: "Delete objectives for a specific day"
    )

    @Argument(help: "Date in YYYY-MM-DD format")
    var date: String

    @Flag(name: .long, help: "Skip confirmation prompt")
    var force: Bool = false

    func run() async throws {
        if !force {
            print("Delete objectives for \(date)? [y/N] ", terminator: "")
            guard let response = readLine(), response.lowercased() == "y" else {
                print("Cancelled")
                return
            }
        }

        let db = try DatabaseHelper()
        let deleted = try await db.deleteDayObjectives(date: date)

        if deleted {
            print("Deleted objectives for \(date)")
        } else {
            print("No objectives found for \(date)")
        }
    }
}
