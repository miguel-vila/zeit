import ArgumentParser
import Foundation

/// View activity history commands
struct ViewCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "view",
        abstract: "View activity history",
        subcommands: [
            ViewTodayCommand.self,
            ViewYesterdayCommand.self,
            ViewDayCommand.self,
            ViewAllCommand.self,
            ViewSummarizeCommand.self,
            ViewObjectivesCommand.self,
            SetObjectivesCommand.self,
            DeleteObjectivesCommand.self,
        ]
    )
}

// MARK: - Today

struct ViewTodayCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "today",
        abstract: "View today's activities"
    )

    @Option(name: .long, help: "Only show activities in this group")
    var group: ActivityGroup?

    func run() async throws {
        let today = DateHelpers.todayString()
        try await ViewHelpers.printDayActivities(date: today, group: group)
    }
}

// MARK: - Yesterday

struct ViewYesterdayCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "yesterday",
        abstract: "View yesterday's activities"
    )

    @Option(name: .long, help: "Only show activities in this group")
    var group: ActivityGroup?

    func run() async throws {
        let yesterday = DateHelpers.yesterdayString()
        try await ViewHelpers.printDayActivities(date: yesterday, group: group)
    }
}

// MARK: - Specific Day

struct ViewDayCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "day",
        abstract: "View activities for a specific day"
    )

    @Argument(help: "Date in YYYY-MM-DD format")
    var date: String

    @Option(name: .long, help: "Only show activities in this group")
    var group: ActivityGroup?

    func run() async throws {
        try await ViewHelpers.printDayActivities(date: date, group: group)
    }
}

// MARK: - All Days

struct ViewAllCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "all",
        abstract: "View summary of all tracked days"
    )

    func run() async throws {
        let db = try DatabaseHelper()
        let days = try await db.getAllDays()

        if days.isEmpty {
            print("No activities tracked yet.")
            return
        }

        print("All Tracked Days")
        print("================")
        print("")

        for (date, count) in days {
            print("\(date): \(count) activities")
        }
    }
}

// MARK: - Summarize

struct ViewSummarizeCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "summarize",
        abstract: "Generate AI summary for a day"
    )

    @Argument(help: "Date in YYYY-MM-DD format (defaults to today)")
    var date: String?

    @Option(name: [.short, .long], help: "Override model in format 'provider:model' (e.g., 'openai:gpt-4o-mini')")
    var model: String?

    func run() async throws {
        let targetDate = date ?? DateHelpers.todayString()
        print("Generating summary for \(targetDate)...")

        let db = try DatabaseHelper()

        guard let record = try await db.getDayRecord(date: targetDate) else {
            print("No activities recorded for \(targetDate)")
            return
        }

        let objectives = try await db.getDayObjectives(date: targetDate)

        // Determine provider and model
        let providerName: String
        let modelName: String
        if let override = model {
            (providerName, modelName) = try parseModelOverride(override)
        } else {
            let config = ZeitConfig.load()
            providerName = config.models.text.provider
            modelName = config.models.text.model
        }

        let llmProvider = try LLMProviderFactory.create(provider: providerName, model: modelName)
        let summarizer = DaySummarizer(provider: llmProvider)

        guard let result = try await summarizer.summarize(
            activities: record.activities,
            objectives: objectives
        ) else {
            print("No non-idle activities recorded for \(targetDate)")
            return
        }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        let separator = "=" .repeated(70)

        print("")
        print(separator)
        print("Day Summary for \(targetDate)")
        print(separator)
        print("(\(timeFormatter.string(from: result.startTime)) - \(timeFormatter.string(from: result.endTime)))")

        if let obj = objectives {
            print("Main objective: \(obj.mainObjective)")
            if !obj.secondaryObjectives.isEmpty {
                print("Secondary: \(obj.secondaryObjectives.joined(separator: ", "))")
            }
        }

        print("")
        print(result.summary)
        if let alignment = result.objectivesAlignment {
            print("")
            print("**Objectives Alignment:**")
            print(alignment)
        }
        print("")
        print("**Percentages Breakdown:**")
        print("")
        print(result.percentagesBreakdown)
        print(separator)
    }
}

/// Parse a model override string in format "provider:model".
private func parseModelOverride(_ override: String) throws -> (provider: String, model: String) {
    guard override.contains(":") else {
        throw SummarizeError.invalidFormat(override)
    }
    let parts = override.split(separator: ":", maxSplits: 1)
    let provider = String(parts[0])
    let model = String(parts[1])

    guard ["mlx", "openai"].contains(provider) else {
        throw SummarizeError.unknownProvider(provider)
    }
    guard !model.isEmpty else {
        throw SummarizeError.emptyModel
    }
    return (provider, model)
}

enum SummarizeError: LocalizedError {
    case invalidFormat(String)
    case unknownProvider(String)
    case emptyModel

    var errorDescription: String? {
        switch self {
        case .invalidFormat(let value):
            return "Invalid format '\(value)'. Expected 'provider:model' (e.g., 'openai:gpt-4o-mini')"
        case .unknownProvider(let provider):
            return "Unknown provider '\(provider)'. Supported: mlx, openai"
        case .emptyModel:
            return "Model name cannot be empty"
        }
    }
}

// MARK: - Objectives

struct ViewObjectivesCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "objectives",
        abstract: "View objectives for a day"
    )

    @Argument(help: "Date in YYYY-MM-DD format (defaults to today)")
    var date: String?

    func run() async throws {
        let targetDate = date ?? DateHelpers.todayString()
        let db = try DatabaseHelper()

        guard let objectives = try await db.getDayObjectives(date: targetDate) else {
            print("No objectives set for \(targetDate)")
            return
        }

        print("Objectives for \(targetDate)")
        print("=" .repeated(30))
        print("")
        print("Main: \(objectives.mainObjective)")

        if !objectives.secondaryObjectives.isEmpty {
            print("")
            print("Secondary:")
            for (index, obj) in objectives.secondaryObjectives.enumerated() {
                print("  \(index + 1). \(obj)")
            }
        }
    }
}

// MARK: - Set Objectives

struct SetObjectivesCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "set-objectives",
        abstract: "Set objectives for a day"
    )

    @Option(name: .long, help: "Main objective for the day")
    var main: String

    @Option(name: .long, help: "First optional secondary objective")
    var opt1: String?

    @Option(name: .long, help: "Second optional secondary objective")
    var opt2: String?

    @Argument(help: "Date in YYYY-MM-DD format (defaults to today)")
    var date: String?

    func run() async throws {
        let targetDate = date ?? DateHelpers.todayString()
        let secondary = [opt1, opt2].compactMap { $0 }

        let db = try DatabaseHelper()
        try await db.saveDayObjectives(date: targetDate, main: main, secondary: secondary)

        print("Objectives saved for \(targetDate)")
    }
}

// MARK: - Delete Objectives

struct DeleteObjectivesCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "delete-objectives",
        abstract: "Delete objectives for a day"
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
            print("Objectives deleted for \(date)")
        } else {
            print("No objectives found for \(date)")
        }
    }
}

// MARK: - Helpers

/// The day keys the CLI defaults to, attributed per `tracking.day_start_hour`.
///
/// Both come from `DayAttribution`, the one place a day key is computed, so a
/// `zeit view today` cannot name a different day than `zeit track` wrote to.
enum DateHelpers {
    static func todayString() -> String {
        DayAttribution.current.today()
    }

    static func yesterdayString() -> String {
        DayAttribution.current.yesterday()
    }
}

enum ViewHelpers {
    static func printDayActivities(date: String, group: ActivityGroup? = nil) async throws {
        let db = try DatabaseHelper()

        guard let record = try await db.getDayRecord(date: date) else {
            print("No activities found for \(date)")
            return
        }

        let activityTypes = try await db.getActivityTypes()
        let groupsByID = Dictionary(
            activityTypes.map { ($0.id, $0.group) },
            uniquingKeysWith: { first, _ in first }
        )

        let entries: [ActivityEntry]
        if let group {
            entries = record.activities.filter { groupsByID[$0.activity.rawValue] == group }
        } else {
            entries = record.activities
        }

        let heading = group.map { "Activities for \(date) — \($0.displayName)" }
            ?? "Activities for \(date)"
        print(heading)
        print("=" .repeated(40))
        print("")

        if entries.isEmpty {
            print("No activities in this group for \(date)")
            return
        }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        let isoFormatter = ISO8601DateFormatter()

        for entry in entries {
            let timeStr: String
            if let entryDate = isoFormatter.date(from: entry.timestamp) {
                timeStr = timeFormatter.string(from: entryDate)
            } else {
                timeStr = "??:??"
            }

            let icon = icon(for: entry, groupsByID: groupsByID)
            if let description = entry.description {
                print("\(timeStr) \(icon) \(entry.activity.displayName) — \(description)")
            } else {
                print("\(timeStr) \(icon) \(entry.activity.displayName)")
            }
        }

        print("")
        print("Total: \(entries.count) activities")

        // Calculate breakdown over the entries shown
        let stats = computeActivityBreakdown(
            from: entries, activityTypes: activityTypes, includeIdle: true
        )
        let shares = ActivityGroup.allCases.map {
            "\($0.displayName): \(String(format: "%.1f", share(of: $0, in: stats)))%"
        }
        let extras = [
            "\(ActivityGroup.unclassifiedLabel): \(String(format: "%.1f", unclassifiedShare(in: stats)))%",
            "Idle: \(String(format: "%.1f", idleShare(in: stats)))%",
        ]

        print((shares + extras).joined(separator: " | "))
    }

    private static func icon(
        for entry: ActivityEntry,
        groupsByID: [String: ActivityGroup]
    ) -> String {
        if entry.activity == .idle { return "😴" }
        switch groupsByID[entry.activity.rawValue] {
        case .work: return "💼"
        case .personalProjects: return "🚀"
        case .personal: return "🏠"
        case nil: return "❓"
        }
    }
}

// String repetition helper
extension String {
    func repeated(_ times: Int) -> String {
        String(repeating: self, count: times)
    }
}
