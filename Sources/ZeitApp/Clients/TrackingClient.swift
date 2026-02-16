import Dependencies
import DependenciesMacros
import Foundation

// MARK: - Client Interface

@DependencyClient
struct TrackingClient: Sendable {
    /// Check if tracking is currently active (stop flag doesn't exist)
    var isTrackingActive: @Sendable () -> Bool = { false }

    /// Check if current time is within configured work hours
    var isWithinWorkHours: @Sendable () -> Bool = { false }

    /// Get a message describing work hours status
    var getWorkHoursMessage: @Sendable () -> String = { "" }

    /// Start tracking (remove stop flag)
    var startTracking: @Sendable () async throws -> Void

    /// Stop tracking (create stop flag)
    var stopTracking: @Sendable () async throws -> Void

    /// Get the current tracking state
    var getTrackingState: @Sendable () -> TrackingState = { .pausedManual }
}

// MARK: - Dependency Registration

extension DependencyValues {
    var trackingClient: TrackingClient {
        get { self[TrackingClient.self] }
        set { self[TrackingClient.self] = newValue }
    }
}

// MARK: - Live Implementation

extension TrackingClient: DependencyKey {
    static let liveValue: TrackingClient = {
        let helper = TrackingHelper()

        return TrackingClient(
            isTrackingActive: {
                helper.isTrackingActive()
            },
            isWithinWorkHours: {
                helper.isWithinWorkHours()
            },
            getWorkHoursMessage: {
                helper.getWorkHoursMessage()
            },
            startTracking: {
                try helper.startTracking()
            },
            stopTracking: {
                try helper.stopTracking()
            },
            getTrackingState: {
                helper.getTrackingState()
            }
        )
    }()
}

// MARK: - Helper

private struct TrackingHelper: Sendable {
    private static let dataDir = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/zeit")

    private static var stopFlagPath: URL {
        dataDir.appendingPathComponent(".zeit_stop")
    }

    func isTrackingActive() -> Bool {
        !FileManager.default.fileExists(atPath: Self.stopFlagPath.path)
    }

    func isWithinWorkHours() -> Bool {
        let config = loadConfig()

        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let weekday = calendar.component(.weekday, from: now)

        // Check if today is a configured work day
        guard let day = ZeitConfig.Weekday(rawValue: weekday),
              config.workDays.contains(day) else {
            return false
        }

        let currentMinutes = hour * 60 + minute
        let startMinutes = config.startHour * 60 + config.startMinute
        let endMinutes = config.endHour * 60 + config.endMinute

        return currentMinutes >= startMinutes && currentMinutes < endMinutes
    }

    func getWorkHoursMessage() -> String {
        let config = loadConfig()

        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let weekday = calendar.component(.weekday, from: now)

        guard let day = ZeitConfig.Weekday(rawValue: weekday),
              config.workDays.contains(day) else {
            let dayNames = config.workDays.sorted().map(\.shortName).joined(separator: ", ")
            return "Outside work days (\(dayNames))"
        }

        let currentMinutes = hour * 60 + minute
        let startMinutes = config.startHour * 60 + config.startMinute
        let endMinutes = config.endHour * 60 + config.endMinute

        if currentMinutes < startMinutes {
            return "Before work hours (starts \(formatTime(config.startHour, config.startMinute)))"
        }

        if currentMinutes >= endMinutes {
            return "After work hours (ended \(formatTime(config.endHour, config.endMinute)))"
        }

        return "Within work hours"
    }

    private func formatTime(_ hour: Int, _ minute: Int) -> String {
        String(format: "%d:%02d", hour, minute)
    }

    func startTracking() throws {
        let path = Self.stopFlagPath
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
    }

    func stopTracking() throws {
        let path = Self.stopFlagPath
        FileManager.default.createFile(atPath: path.path, contents: nil)
    }

    func getTrackingState() -> TrackingState {
        let withinWorkHours = isWithinWorkHours()
        let manuallyStopped = !isTrackingActive()

        if !withinWorkHours {
            let message = getWorkHoursMessage()
            if isBeforeWorkHours() {
                return .beforeWorkHours(message: message)
            } else {
                return .afterWorkHours(message: message)
            }
        }

        if manuallyStopped {
            return .pausedManual
        }

        return .active
    }

    /// Whether the current time is before work hours start (on a work day)
    func isBeforeWorkHours() -> Bool {
        let config = loadConfig()
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let weekday = calendar.component(.weekday, from: now)

        guard let day = ZeitConfig.Weekday(rawValue: weekday),
              config.workDays.contains(day) else {
            return false
        }

        let currentMinutes = hour * 60 + minute
        let startMinutes = config.startHour * 60 + config.startMinute

        return currentMinutes < startMinutes
    }

    // MARK: - Config Loading

    private func loadConfig() -> ZeitConfig.WorkHoursConfig {
        ZeitConfig.load().workHours
    }
}
