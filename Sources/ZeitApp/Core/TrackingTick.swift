import Foundation

/// Why a tracking tick runs, or why it holds off.
///
/// launchd fires `zeit track` every 60 seconds whatever the config says, so
/// every reason to hold off is decided here: `zeit track` acts on the decision
/// and logs it, `zeit doctor` reports it without acting.
enum TrackingTickDecision: Equatable, Sendable {
    case track
    case outsideSchedule
    case paused
    case onBattery
    /// The configured cadence has not elapsed since the newest stored entry.
    case tooSoon(elapsed: TimeInterval, interval: Int)

    var tracks: Bool { self == .track }

    /// Why this tick is skipped, in one line, or nil when it tracks.
    ///
    /// The tracker log and `zeit doctor` share this wording so a skipped tick
    /// cannot be explained two different ways.
    var skipReason: String? {
        switch self {
        case .track:
            return nil
        case .outsideSchedule:
            return "outside the tracking schedule"
        case .paused:
            return "tracking is paused (stop flag exists)"
        case .onBattery:
            return "on battery power, and tracking.skip_on_battery is on"
        case .tooSoon(let elapsed, let interval):
            let ago = Int(elapsed.rounded())
            return "last entry \(ago)s ago, under the \(interval)s cadence"
        }
    }
}

/// The gate every tracking run passes through.
enum TrackingTick {
    /// launchd fires on an approximate interval, and an entry is timestamped a
    /// moment into the run rather than when launchd woke it, so two
    /// consecutive ticks can land a little under `interval_seconds` apart.
    /// Without this slack a default install would skip every other tick and
    /// track at half the configured cadence.
    static let cadenceSlack: TimeInterval = 5

    /// Whether a tick at `now` should track.
    ///
    /// Checks run cheapest first, and `newestEntry` is a closure because the
    /// cadence is the only gate that needs the database: a tick held off by
    /// the schedule, the stop flag or the battery never reads it.
    static func decide(
        now: Date = Date(),
        schedule: ZeitConfig.ScheduleConfig,
        tracking: ZeitConfig.TrackingConfig,
        isTrackingActive: Bool,
        isOnBattery: Bool,
        calendar: Calendar = .current,
        newestEntry: @Sendable () async -> Date?
    ) async -> TrackingTickDecision {
        guard schedule.contains(now, calendar: calendar) else {
            return .outsideSchedule
        }

        guard isTrackingActive else {
            return .paused
        }

        if tracking.skipOnBattery, isOnBattery {
            return .onBattery
        }

        guard let newest = await newestEntry() else {
            // Nothing stored yet, so no cadence to be under.
            return .track
        }

        let elapsed = now.timeIntervalSince(newest)
        // A newest entry in the future — a clock change, say — reads as due
        // rather than as a cadence that can never elapse.
        guard elapsed >= 0 else { return .track }

        guard elapsed + cadenceSlack >= Double(tracking.intervalSeconds) else {
            return .tooSoon(elapsed: elapsed, interval: tracking.intervalSeconds)
        }

        return .track
    }
}
