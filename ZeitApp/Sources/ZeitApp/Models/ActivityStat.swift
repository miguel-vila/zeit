import Foundation

/// Statistics for a single activity type
struct ActivityStat: Equatable, Identifiable, Sendable {
    let activity: Activity
    let count: Int
    let percentage: Double

    var id: String { activity.rawValue }

    /// Category label for grouping
    var category: String {
        activity.isWork ? "work" : "personal"
    }
}

/// Compute activity breakdown from a list of entries
func computeActivityBreakdown(
    from activities: [ActivityEntry],
    includeIdle: Bool = false
) -> [ActivityStat] {
    let filtered = includeIdle
        ? activities
        : activities.filter { $0.activity != .idle }

    guard !filtered.isEmpty else { return [] }

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
                percentage: (Double(count) / total) * 100.0
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
