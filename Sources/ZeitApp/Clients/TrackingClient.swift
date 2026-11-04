import Dependencies
import DependenciesMacros
import Foundation

// MARK: - Client Interface

@DependencyClient
struct TrackingClient: Sendable {
    /// Check if tracking is currently active (stop flag doesn't exist)
    var isTrackingActive: @Sendable () -> Bool = { false }

    /// Check if the current moment is inside the configured tracking schedule
    var isWithinSchedule: @Sendable () -> Bool = { false }

    /// Get a message describing the schedule status
    var getScheduleMessage: @Sendable () -> String = { "" }

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
            isWithinSchedule: {
                helper.isWithinSchedule()
            },
            getScheduleMessage: {
                helper.getScheduleMessage()
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

    func isWithinSchedule() -> Bool {
        loadSchedule().contains(Date())
    }

    func getScheduleMessage() -> String {
        loadSchedule().statusMessage(at: Date())
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
        let schedule = loadSchedule()
        let now = Date()

        if !schedule.contains(now) {
            return .outsideSchedule(message: schedule.statusMessage(at: now))
        }

        if !isTrackingActive() {
            return .pausedManual
        }

        return .active
    }

    // MARK: - Config Loading

    private func loadSchedule() -> ZeitConfig.ScheduleConfig {
        ZeitConfig.load().schedule
    }
}
