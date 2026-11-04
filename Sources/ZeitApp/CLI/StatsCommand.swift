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

    @Option(name: .long, help: "Only count activities in this group")
    var group: ActivityGroup?

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

        let activityTypes = try await db.getActivityTypes()
        var activities = includeIdle ? record.activities : record.nonIdleActivities

        if let group {
            let groupIDs = Set(activityTypes.filter { $0.group == group }.map(\.id))
            activities = activities.filter { groupIDs.contains($0.activity.rawValue) }
        }

        let stats = computeActivityBreakdown(
            from: activities, activityTypes: activityTypes, includeIdle: includeIdle
        )

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
            let groupPercentages: [String: Double]
            let unclassifiedPercentage: Double
            let idlePercentage: Double

            enum CodingKeys: String, CodingKey {
                case date
                case totalSamples = "total_samples"
                case activities
                case groupPercentages = "group_percentages"
                case unclassifiedPercentage = "unclassified_percentage"
                case idlePercentage = "idle_percentage"
            }
        }

        struct ActivityStatOutput: Encodable {
            let activity: String
            let count: Int
            let percentage: Double
            let group: String?
        }

        let output = StatsOutput(
            date: date,
            totalSamples: total,
            activities: stats.map {
                ActivityStatOutput(
                    activity: $0.activity.rawValue,
                    count: $0.count,
                    percentage: $0.percentage,
                    group: $0.group?.rawValue
                )
            },
            groupPercentages: Dictionary(
                uniqueKeysWithValues: ActivityGroup.allCases.map {
                    ($0.rawValue, share(of: $0, in: stats))
                }
            ),
            unclassifiedPercentage: unclassifiedShare(in: stats),
            idlePercentage: idleShare(in: stats)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(output)
        print(String(data: data, encoding: .utf8)!)
    }

    private func printStatsTable(date: String, stats: [ActivityStat], total: Int) {
        let heading = group.map { "Activity Statistics for \(date) — \($0.displayName)" }
            ?? "Activity Statistics for \(date)"
        print(heading)
        print("=" .repeated(50))
        print("")

        print("Summary:")
        print("  Total samples: \(total)")
        for group in ActivityGroup.allCases {
            let label = "\(group.displayName):".padding(
                toLength: 18, withPad: " ", startingAt: 0
            )
            print("  \(label)\(String(format: "%5.1f", share(of: group, in: stats)))%")
        }
        let unclassifiedLabel = "\(ActivityGroup.unclassifiedLabel):".padding(
            toLength: 18, withPad: " ", startingAt: 0
        )
        print("  \(unclassifiedLabel)\(String(format: "%5.1f", unclassifiedShare(in: stats)))%")
        print("  \("Idle:".padding(toLength: 18, withPad: " ", startingAt: 0))\(String(format: "%5.1f", idleShare(in: stats)))%")
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
