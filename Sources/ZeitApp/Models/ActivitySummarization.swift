import Foundation
import os

private let logger = Logger(subsystem: "com.zeit", category: "ActivitySummarization")

/// A run of consecutive activities of the same type.
struct ActivityRun: Equatable, Sendable {
    let activity: Activity
    let startTime: Date
    let endTime: Date
    let durationMinutes: Int
    let reasonings: [String]
}

/// Container for the full condensed activity data.
struct CondensedActivitySummary: Equatable, Sendable {
    let runs: [ActivityRun]
    let percentageBreakdown: [ActivityStat]
    let totalActiveMinutes: Int
    let originalEntryCount: Int
    let condensedEntryCount: Int
}

/// Group consecutive activities of the same type (excluding idle).
///
/// - Parameter entries: List of `ActivityEntry`, expected to be chronologically ordered.
/// - Returns: List of `ActivityRun`, one per consecutive sequence of same activity type.
func groupConsecutiveActivities(from entries: [ActivityEntry]) -> [ActivityRun] {
    let nonIdle = entries.filter { $0.activity != .idle }
    guard let first = nonIdle.first else { return [] }

    var runs: [ActivityRun] = []
    var currentEntries: [ActivityEntry] = [first]

    for entry in nonIdle.dropFirst() {
        if entry.activity == currentEntries[0].activity {
            currentEntries.append(entry)
        } else {
            runs.append(createRun(from: currentEntries))
            currentEntries = [entry]
        }
    }

    // Don't forget the last group
    runs.append(createRun(from: currentEntries))
    return runs
}

/// Build a complete condensed summary from raw activity entries.
///
/// Groups consecutive activities of the same type and computes percentage breakdown.
///
/// - Parameter entries: List of `ActivityEntry`.
/// - Returns: `CondensedActivitySummary` with grouped activities and percentages.
func buildCondensedSummary(
    from entries: [ActivityEntry],
    activityTypes: [ActivityType] = ActivityType.defaultTypes
) -> CondensedActivitySummary {
    let nonIdle = entries.filter { $0.activity != .idle }
    let runs = groupConsecutiveActivities(from: entries)
    logger.info("Grouped \(nonIdle.count) activities into \(runs.count) runs")

    let percentageBreakdown = computeActivityBreakdown(
        from: entries, activityTypes: activityTypes, includeIdle: false
    )

    return CondensedActivitySummary(
        runs: runs,
        percentageBreakdown: percentageBreakdown,
        totalActiveMinutes: nonIdle.count,
        originalEntryCount: nonIdle.count,
        condensedEntryCount: runs.count
    )
}

// MARK: - Private

private let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    return formatter
}()

/// Create an `ActivityRun` from a list of consecutive entries of the same type.
private func createRun(from entries: [ActivityEntry]) -> ActivityRun {
    let startTime = isoFormatter.date(from: entries[0].timestamp) ?? Date()
    let endTime = isoFormatter.date(from: entries[entries.count - 1].timestamp) ?? Date()
    let reasonings = entries.compactMap(\.reasoning)

    return ActivityRun(
        activity: entries[0].activity,
        startTime: startTime,
        endTime: endTime,
        durationMinutes: entries.count,
        reasonings: reasonings
    )
}
