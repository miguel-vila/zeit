import Foundation

/// Statistics for a single activity type
struct ActivityStat: Equatable, Identifiable, Sendable {
    let activity: Activity
    let count: Int
    let percentage: Double
    /// The group of the activity type behind this stat, or `nil` when the type is
    /// no longer configured (or for the reserved `idle` type).
    let group: ActivityGroup?

    var id: String { activity.rawValue }

    var isIdle: Bool { activity == .idle }

    /// Label used wherever this stat is shown outside of a group section.
    var groupLabel: String {
        if isIdle { return "Idle" }
        return group?.displayName ?? ActivityGroup.unclassifiedLabel
    }
}

/// Compute activity breakdown from a list of entries.
///
/// The group of each stat comes from the matching entry in `activityTypes`. An id
/// that is not in the type table has no group and reports as Unclassified — it is
/// never folded into a group it was not labelled with.
func computeActivityBreakdown(
    from activities: [ActivityEntry],
    activityTypes: [ActivityType] = ActivityType.defaultTypes,
    includeIdle: Bool = false
) -> [ActivityStat] {
    let filtered = includeIdle
        ? activities
        : activities.filter { $0.activity != .idle }

    guard !filtered.isEmpty else { return [] }

    let groupsByID = Dictionary(
        activityTypes.map { ($0.id, $0.group) },
        uniquingKeysWith: { first, _ in first }
    )

    // Count occurrences of each activity
    var counts: [Activity: Int] = [:]
    for entry in filtered {
        counts[entry.activity, default: 0] += 1
    }

    let total = Double(filtered.count)

    // Convert to stats and sort by percentage descending
    return counts
        .map { activity, count in
            ActivityStat(
                activity: activity,
                count: count,
                percentage: (Double(count) / total) * 100.0,
                group: activity == .idle ? nil : groupsByID[activity.rawValue]
            )
        }
        .sorted { $0.percentage > $1.percentage }
}

/// Sum the percentages of the stats belonging to `group`.
func share(of group: ActivityGroup, in stats: [ActivityStat]) -> Double {
    stats
        .filter { $0.group == group }
        .reduce(0.0) { $0 + $1.percentage }
}

/// Sum the percentages of the stats whose type is no longer configured.
func unclassifiedShare(in stats: [ActivityStat]) -> Double {
    stats
        .filter { !$0.isIdle && $0.group == nil }
        .reduce(0.0) { $0 + $1.percentage }
}

/// Sum the percentages of the idle stats, if idle was included in the breakdown.
func idleShare(in stats: [ActivityStat]) -> Double {
    stats
        .filter(\.isIdle)
        .reduce(0.0) { $0 + $1.percentage }
}
