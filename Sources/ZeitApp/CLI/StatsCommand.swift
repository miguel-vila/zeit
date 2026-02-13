import ArgumentParser
import Foundation

/// Activity statistics command
struct StatsCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "stats",
        abstract: "Show activity statistics"
    )

    @Argument(help: "Date in YYYY-MM-DD format (defaults to today)")
    var date: String?

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    @Flag(name: .long, help: "Include idle time in statistics")
    var includeIdle: Bool = false

    func run() async throws {
        let targetDate = date ?? DateHelpers.todayString()
        let db = try DatabaseHelper()

        guard let record = try await db.getDayRecord(date: targetDate) else {
            if json {
                print("{\"error\": \"No activities found for \(targetDate)\"}")
            } else {
                print("No activities found for \(targetDate)")
            }
            return
        }

        let activities = includeIdle ? record.activities : record.nonIdleActivities
        let stats = computeActivityBreakdown(from: activities)

        if json {
            try printStatsJSON(date: targetDate, stats: stats, total: activities.count)
        } else {
            printStatsTable(date: targetDate, stats: stats, total: activities.count)
        }
    }

    private func printStatsJSON(date: String, stats: [ActivityStat], total: Int) throws {
        struct StatsOutput: Encodable {
            let date: String
            let totalSamples: Int
            let activities: [ActivityStatOutput]
            let workPercentage: Double
            let personalPercentage: Double
            let idlePercentage: Double

            enum CodingKeys: String, CodingKey {
                case date
                case totalSamples = "total_samples"
                case activities
                case workPercentage = "work_percentage"
                case personalPercentage = "personal_percentage"
                case idlePercentage = "idle_percentage"
            }
        }

        struct ActivityStatOutput: Encodable {
            let activity: String
            let count: Int
            let percentage: Double
            let category: String
        }

        let workPct = stats.filter { $0.category == "work" }.reduce(0.0) { $0 + $1.percentage }
        let personalPct = stats.filter { $0.category == "personal" }.reduce(0.0) { $0 + $1.percentage }
        let idlePct = stats.filter { $0.category == "system" }.reduce(0.0) { $0 + $1.percentage }

        let output = StatsOutput(
            date: date,
            totalSamples: total,
            activities: stats.map {
                ActivityStatOutput(
                    activity: $0.activity.rawValue,
                    count: $0.count,
                    percentage: $0.percentage,
                    category: $0.category
                )
            },
            workPercentage: workPct,
            personalPercentage: personalPct,
            idlePercentage: idlePct
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(output)
        print(String(data: data, encoding: .utf8)!)
    }

    private func printStatsTable(date: String, stats: [ActivityStat], total: Int) {
        print("Activity Statistics for \(date)")
        print("=" .repeated(50))
        print("")

        let workPct = stats.filter { $0.category == "work" }.reduce(0.0) { $0 + $1.percentage }
        let personalPct = stats.filter { $0.category == "personal" }.reduce(0.0) { $0 + $1.percentage }
        let idlePct = stats.filter { $0.category == "system" }.reduce(0.0) { $0 + $1.percentage }

        print("Summary:")
        print("  Total samples: \(total)")
        print("  Work:     \(String(format: "%5.1f", workPct))%")
        print("  Personal: \(String(format: "%5.1f", personalPct))%")
        print("  Idle:     \(String(format: "%5.1f", idlePct))%")
        print("")

        print("Breakdown:")
        print("-" .repeated(50))

        // Sort by percentage descending
        let sortedStats = stats.sorted { $0.percentage > $1.percentage }

        for stat in sortedStats {
            let bar = String(repeating: "█", count: Int(stat.percentage / 5))
            print(String(format: "  %-25s %3d (%5.1f%%) %@",
                         (stat.activity.rawValue as NSString).utf8String!,
                         stat.count,
                         stat.percentage,
                         bar))
        }
    }
}
