import Foundation

/// Represents the current tracking state of the app
enum TrackingState: Equatable, Sendable {
    case active
    case pausedManual
    case outsideWorkHours(message: String)

    /// SF Symbol name for the menubar icon
    var iconName: String {
        switch self {
        case .active:
            return "chart.bar.fill"
        case .pausedManual:
            return "pause.fill"
        case .outsideWorkHours:
            return "moon.fill"
        }
    }

    /// Status message to display in the menu
    var statusMessage: String {
        switch self {
        case .active:
            return "Tracking active"
        case .pausedManual:
            return "Tracking paused (manual)"
        case .outsideWorkHours(let message):
            return message
        }
    }

    /// Whether the user can toggle tracking on/off
    var canToggle: Bool {
        switch self {
        case .active, .pausedManual:
            return true
        case .outsideWorkHours:
            return false
        }
    }

    /// Whether tracking is currently running
    var isActive: Bool {
        self == .active
    }
}
