import Foundation

/// How long ago the newest entry was stored, as the menubar reports it.
///
/// The one cue that does not depend on knowing why the tracker is quiet: a
/// hold Zeit models, a launchd throttle it does not, a classification that
/// fails every tick — all of them widen this gap. A status that claims to be
/// active beside an age of hours disagrees with itself, which is what makes
/// someone look.
struct EntryAge: Equatable, Sendable {
    /// How many cadences may pass before a gap reads as a fault.
    ///
    /// launchd fires on an approximate interval and a tick can be held off for
    /// a reason that clears itself, so one late tick says nothing. Three
    /// cadences is long enough that a healthy machine never reaches it.
    static let staleAfterIntervals = 3

    let seconds: TimeInterval

    /// Whether the gap is wider than the configured cadence can account for.
    let isStale: Bool

    /// A gap measured against the cadence that was meant to fill it. A newest
    /// entry in the future — a clock change, say — reads as no gap at all.
    init(seconds: TimeInterval, intervalSeconds: Int) {
        self.seconds = max(0, seconds)
        self.isStale = self.seconds > Double(intervalSeconds * Self.staleAfterIntervals)
    }

    /// Coarse on purpose: the exact second is never the question, and the
    /// label shares a 300pt row with the status it contradicts.
    var summary: String {
        let minutes = Int(seconds) / 60

        guard minutes >= 1 else { return "just now" }
        guard minutes >= 60 else { return "\(minutes)m" }

        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }
}
