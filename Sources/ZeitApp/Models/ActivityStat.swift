import Foundation

/// Statistics for a single activity type
struct ActivityStat: Equatable, Identifiable, Sendable {
    let activity: Activity
    let count: Int
    let percentage: Double
    let isWork: Bool

    var id: String { activity.rawValue }

    /// Category label for grouping
    var category: String {
        if activity == .idle { return "system" }
        return isWork ? "work" : "personal"
    }
}

/// Compute activity breakdown from a list of entries.
///
/// Uses the provided `activityTypes` to determine work/personal classification.
/// Unknown types default to personal.
func computeActivityBreakdown(
    from activities: [ActivityEntry],
    activityTypes: [ActivityType] = ActivityType.defaultTypes,
    includeIdle: Bool = false
) -> [ActivityStat] {
    let filtered = includeIdle
        ? activities
        : activities.filter { $0.activity != .idle }

    guard !filtered.isEmpty else { return [] }

    // Build lookup for isWork
    let workIDs = Set(activityTypes.filter(\.isWork).map(\.id))

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
                isWork: workIDs.contains(activity.rawValue)
            )
        }
        .sorted { $0.percentage > $1.percentage }
}

/// Calculate work percentage from activity stats
func workPercentage(from stats: [ActivityStat]) -> Double {
    stats
        .filter { $0.category == "work" }
        .reduce(0.0) { $0 + $1.percentage }
}
