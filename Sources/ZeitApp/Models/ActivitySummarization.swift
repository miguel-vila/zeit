import Foundation
import os

private let logger = Logger(subsystem: "com.zeit", category: "ActivitySummarization")

/// A group of consecutive activities of the same type.
struct ActivityGroup: Equatable, Sendable {
    let activity: Activity
    let startTime: Date
    let endTime: Date
    let durationMinutes: Int
    let reasonings: [String]
}

/// Container for the full condensed activity data.
struct CondensedActivitySummary: Equatable, Sendable {
    let groups: [ActivityGroup]
    let percentageBreakdown: [ActivityStat]
    let totalActiveMinutes: Int
    let originalEntryCount: Int
    let condensedEntryCount: Int
}

/// Group consecutive activities of the same type (excluding idle).
///
/// - Parameter entries: List of `ActivityEntry`, expected to be chronologically ordered.
/// - Returns: List of `ActivityGroup`, one per consecutive sequence of same activity type.
func groupConsecutiveActivities(from entries: [ActivityEntry]) -> [ActivityGroup] {
    let nonIdle = entries.filter { $0.activity != .idle }
    guard let first = nonIdle.first else { return [] }

    var groups: [ActivityGroup] = []
    var currentEntries: [ActivityEntry] = [first]

    for entry in nonIdle.dropFirst() {
        if entry.activity == currentEntries[0].activity {
            currentEntries.append(entry)
        } else {
            groups.append(createGroup(from: currentEntries))
            currentEntries = [entry]
        }
    }

    // Don't forget the last group
    groups.append(createGroup(from: currentEntries))
    return groups
}

/// Build a complete condensed summary from raw activity entries.
///
/// Groups consecutive activities of the same type and computes percentage breakdown.
///
/// - Parameter entries: List of `ActivityEntry`.
/// - Returns: `CondensedActivitySummary` with grouped activities and percentages.
func buildCondensedSummary(from entries: [ActivityEntry]) -> CondensedActivitySummary {
    let nonIdle = entries.filter { $0.activity != .idle }
    let groups = groupConsecutiveActivities(from: entries)
    logger.info("Grouped \(nonIdle.count) activities into \(groups.count) groups")

    let percentageBreakdown = computeActivityBreakdown(from: entries, includeIdle: false)

    return CondensedActivitySummary(
        groups: groups,
        percentageBreakdown: percentageBreakdown,
        totalActiveMinutes: nonIdle.count,
        originalEntryCount: nonIdle.count,
        condensedEntryCount: groups.count
    )
}

// MARK: - Private

private let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    return formatter
}()

/// Create an `ActivityGroup` from a list of consecutive entries of the same type.
private func createGroup(from entries: [ActivityEntry]) -> ActivityGroup {
    let startTime = isoFormatter.date(from: entries[0].timestamp) ?? Date()
    let endTime = isoFormatter.date(from: entries[entries.count - 1].timestamp) ?? Date()
    let reasonings = entries.compactMap(\.reasoning)

    return ActivityGroup(
        activity: entries[0].activity,
        startTime: startTime,
        endTime: endTime,
        durationMinutes: entries.count,
        reasonings: reasonings
    )
}
