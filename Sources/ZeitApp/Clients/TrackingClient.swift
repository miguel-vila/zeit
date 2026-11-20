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

    /// The configured seconds between entries, which is what the age of the
    /// newest entry has to be read against.
    var cadenceSeconds: @Sendable () -> Int = {
        ZeitConfig.TrackingConfig.minimumIntervalSeconds
    }
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
            },
            cadenceSeconds: {
                ZeitConfig.load().tracking.intervalSeconds
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

    /// The gate the tracker itself runs, minus the cadence.
    ///
    /// The menubar used to re-derive this from the schedule and the stop flag,
    /// which left out the battery and reported an afternoon of held ticks as
    /// "Tracking active".
    func getTrackingState() -> TrackingState {
        let config = ZeitConfig.load()
        let now = Date()

        let decision = TrackingTick.decideWithoutCadence(
            now: now,
            schedule: config.schedule,
            tracking: config.tracking,
            isTrackingActive: isTrackingActive(),
            isOnBattery: PowerSource.isOnBattery()
        )

        return .from(decision) { config.schedule.statusMessage(at: now) }
    }

    // MARK: - Config Loading

    private func loadSchedule() -> ZeitConfig.ScheduleConfig {
        ZeitConfig.load().schedule
    }
}
