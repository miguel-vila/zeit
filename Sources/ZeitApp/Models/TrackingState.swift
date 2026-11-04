import Foundation

/// Represents the current tracking state of the app
enum TrackingState: Equatable, Sendable {
    case active
    case pausedManual
    /// Now is outside the configured tracking schedule. One case rather than a
    /// before/after pair: with several windows, and windows that run overnight,
    /// "before" and "after" no longer name anything.
    case outsideSchedule(message: String)

    /// Status message to display in the menu
    var statusMessage: String {
        switch self {
        case .active:
            return "Tracking active"
        case .pausedManual:
            return "Tracking paused (manual)"
        case .outsideSchedule(let message):
            return message
        }
    }

    /// Whether the user can toggle tracking on/off
    var canToggle: Bool {
        switch self {
        case .active, .pausedManual:
            return true
        case .outsideSchedule:
            return false
        }
    }

    /// Whether tracking is currently running
    var isActive: Bool {
        self == .active
    }

    /// Whether the app is outside its tracking schedule
    var isOutsideSchedule: Bool {
        switch self {
        case .outsideSchedule:
            return true
        case .active, .pausedManual:
            return false
        }
    }
}
