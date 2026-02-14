import Foundation

/// Represents the current tracking state of the app
enum TrackingState: Equatable, Sendable {
    case active
    case pausedManual
    case beforeWorkHours(message: String)
    case afterWorkHours(message: String)

    /// Status message to display in the menu
    var statusMessage: String {
        switch self {
        case .active:
            return "Tracking active"
        case .pausedManual:
            return "Tracking paused (manual)"
        case .beforeWorkHours(let message):
            return message
        case .afterWorkHours(let message):
            return message
        }
    }

    /// Whether the user can toggle tracking on/off
    var canToggle: Bool {
        switch self {
        case .active, .pausedManual:
            return true
        case .beforeWorkHours, .afterWorkHours:
            return false
        }
    }

    /// Whether tracking is currently running
    var isActive: Bool {
        self == .active
    }

    /// Whether the app is outside work hours (before or after)
    var isOutsideWorkHours: Bool {
        switch self {
        case .beforeWorkHours, .afterWorkHours:
            return true
        case .active, .pausedManual:
            return false
        }
    }
}
