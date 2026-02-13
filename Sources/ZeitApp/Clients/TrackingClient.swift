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
        let weekday = calendar.component(.weekday, from: now)

        // Check if it's a weekday (Monday=2 through Friday=6 in Calendar)
        let isWeekday = (2...6).contains(weekday)

        guard isWeekday else { return false }

        return hour >= config.startHour && hour < config.endHour
    }

    func getWorkHoursMessage() -> String {
        let config = loadConfig()

        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let weekday = calendar.component(.weekday, from: now)

        let isWeekday = (2...6).contains(weekday)

        if !isWeekday {
            return "Outside work days (Mon-Fri)"
        }

        if hour < config.startHour {
            return "Before work hours (starts \(config.startHour):00)"
        }

        if hour >= config.endHour {
            return "After work hours (ended \(config.endHour):00)"
        }

        return "Within work hours"
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
            return .outsideWorkHours(message: getWorkHoursMessage())
        }

        if manuallyStopped {
            return .pausedManual
        }

        return .active
    }

    // MARK: - Config Loading

    private func loadConfig() -> ZeitConfig.WorkHoursConfig {
        ZeitConfig.load().workHours
    }
}
