import Foundation

/// One stored entry, read back as evidence of what the tracker did.
///
/// The stored entry says what was classified; this says how it sits among its
/// neighbours — how long since the one before it, and whether the catalog still
/// defines the type it names. Both are things no single entry can answer.
struct TrackingSample: Equatable, Sendable {
    let timestamp: Date
    let activity: Activity

    /// Whether `activity` is a type the catalog still defines.
    ///
    /// An entry stores only the type's ID, so an ID the catalog has lost — a
    /// type deleted or renamed, or one the model invented — reads as
    /// unclassified wherever it is shown. `idle` is not a catalog type and is
    /// always known.
    let isKnownType: Bool

    let device: String?

    /// Time since the previous sample, or `nil` for the oldest in the window.
    ///
    /// This is the cadence as it actually happened, which is the gap between
    /// stored entries rather than the interval the config asks for.
    let sincePrevious: TimeInterval?
}

/// The most recent entries, in the order someone reads them: newest first.
///
/// Kept apart from the database and the CLI so the window, the gaps and the
/// catalog resolution can be exercised on plain entries.
enum RecentSamples {
    /// `idle` is recorded by the tracker itself rather than chosen from the
    /// catalog, so it is never reported as an unknown type.
    static let systemActivities: Set<Activity> = [.idle]

    /// The newest `limit` entries as samples, newest first.
    ///
    /// Entries may arrive in any order and from any day: they are sorted by
    /// their own timestamp, and one with an unparseable timestamp is dropped
    /// rather than guessed at. Gaps are measured before the window is cut, so
    /// the oldest sample in the window still reports the gap that produced it
    /// when an older entry exists.
    static func from(
        entries: [ActivityEntry],
        knownTypeIDs: Set<String>,
        limit: Int
    ) -> [TrackingSample] {
        let dated = entries
            .compactMap { entry -> (Date, ActivityEntry)? in
                entry.date.map { ($0, entry) }
            }
            .sorted { $0.0 < $1.0 }

        let samples = dated.enumerated().map { index, pair -> TrackingSample in
            let (timestamp, entry) = pair
            return TrackingSample(
                timestamp: timestamp,
                activity: entry.activity,
                isKnownType: systemActivities.contains(entry.activity)
                    || knownTypeIDs.contains(entry.activity.rawValue),
                device: entry.device,
                sincePrevious: index > 0
                    ? timestamp.timeIntervalSince(dated[index - 1].0)
                    : nil
            )
        }

        return samples.suffix(max(limit, 0)).reversed()
    }

    /// The middle gap across a window, or `nil` when nothing in it has one.
    ///
    /// The median rather than the mean: a machine asleep for an hour leaves one
    /// enormous gap that would drag an average away from the cadence that the
    /// rest of the window actually ran at.
    static func medianGap(of samples: [TrackingSample]) -> TimeInterval? {
        let gaps = samples.compactMap(\.sincePrevious).sorted()
        guard !gaps.isEmpty else { return nil }
        return gaps[gaps.count / 2]
    }
}
