import Foundation

/// What the menubar says about tracking.
///
/// Built from a `TrackingTickDecision` so the popover, the status icon, the
/// tracker log and `zeit doctor` cannot answer "is Zeit recording?" four
/// different ways. Before this existed the menubar read the schedule and the
/// stop flag only, and reported "Tracking active" through a whole afternoon of
/// ticks held off on battery.
enum TrackingState: Equatable, Sendable {
    case active
    case pausedManual
    /// Now is outside the configured tracking schedule. One case rather than a
    /// before/after pair: with several windows, and windows that run overnight,
    /// "before" and "after" no longer name anything.
    case outsideSchedule(message: String)
    /// Tracking is on and every tick still holds off: the machine runs on
    /// battery and `tracking.skip_on_battery` is set.
    case heldOnBattery

    /// How a tick decision reads in the menubar.
    ///
    /// `.tooSoon` collapses into `.active`: a tick inside the cadence is the
    /// cadence working, and a hold that clears itself within the minute is not
    /// worth a change of colour. The schedule's message is a closure so it is
    /// built only for the state that shows it.
    static func from(
        _ decision: TrackingTickDecision,
        scheduleMessage: () -> String
    ) -> TrackingState {
        switch decision {
        case .track, .tooSoon:
            return .active
        case .paused:
            return .pausedManual
        case .onBattery:
            return .heldOnBattery
        case .outsideSchedule:
            return .outsideSchedule(message: scheduleMessage())
        }
    }

    /// Status message to display in the menu.
    ///
    /// The two holds the user can lift share one shape, so they read as one
    /// family rather than as two unrelated modes.
    var statusMessage: String {
        switch self {
        case .active:
            return "Tracking active"
        case .pausedManual:
            return "Paused — by you"
        case .outsideSchedule(let message):
            return message
        case .heldOnBattery:
            return "Paused — on battery"
        }
    }

    /// Whether the user can toggle tracking on/off.
    ///
    /// A battery hold can be toggled: the stop flag is a separate choice, and
    /// pausing by hand while unplugged still means something.
    var canToggle: Bool {
        switch self {
        case .active, .pausedManual, .heldOnBattery:
            return true
        case .outsideSchedule:
            return false
        }
    }

    /// Whether the user has tracking on, so a widening gap between entries is
    /// a fault rather than a choice.
    ///
    /// A battery hold counts: nothing was turned off, and the gap it opens is
    /// exactly what the user needs told.
    var expectsEntries: Bool {
        switch self {
        case .active, .heldOnBattery:
            return true
        case .pausedManual, .outsideSchedule:
            return false
        }
    }
}
