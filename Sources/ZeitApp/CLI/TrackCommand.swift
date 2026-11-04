import ArgumentParser
import Foundation

/// Single tracking iteration command
struct TrackCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "track",
        abstract: "Run a single tracking iteration"
    )

    @Option(name: .long, help: "Delay in seconds before capturing")
    var delay: Int = 0

    @Flag(name: .long, help: "Ignore the tracking schedule and stop flag")
    var force: Bool = false

    @Flag(name: .long, help: "Keep screenshots in /tmp and print their paths")
    var debug: Bool = false

    #if DEBUG
    @Flag(name: .long, help: "Save sample artifacts (screenshots, prompts, responses) to disk")
    var sample: Bool = false
    #endif

    func run() async throws {
        #if DEBUG
        let shouldForce = force || sample
        #else
        let shouldForce = force
        #endif

        // Loaded once, so the idle entry and a classified one are stamped
        // with the same device name.
        let config = ZeitConfig.load()

        // 1. Schedule, stop flag, battery and cadence (unless --force or --sample)
        if !shouldForce {
            let decision = await CLITrackingHelper().decideTick()
            if let reason = decision.skipReason {
                print("Skipping this tick: \(reason)")
                return
            }
        }

        // 2. Check idle
        if let idleTime = IdleDetection.getIdleTimeSeconds(), idleTime > 300 {
            let seconds = Int(idleTime)
            print("System idle for \(seconds) seconds, recording idle activity")
            let entry = ActivityEntry(
                timestamp: ISO8601DateFormatter().string(from: Date()),
                activity: .idle,
                reasoning: nil,
                description: "System idle for \(seconds) seconds",
                device: config.device.name
            )
            let db = try DatabaseHelper()
            try await db.insertActivity(entry)
            return
        }

        // 3. Delay if requested
        if delay > 0 {
            print("Waiting \(delay) seconds...")
            try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
        }

        // 4. Capture and identify activity
        print("Capturing screenshots...")

        do {
            let identifier = ActivityIdentifier(
                visionModel: config.models.vision,
                textModel: config.models.text.model,
                textProvider: config.models.text.provider
            )
            #if DEBUG
            let result = try await identifier.identifyCurrentActivity(keepScreenshots: debug, debug: debug, sample: sample)
            #else
            let result = try await identifier.identifyCurrentActivity(keepScreenshots: debug, debug: debug)
            #endif

            print("Activity: \(result.activity.displayName)")
            print("Reasoning: \(result.reasoning ?? "N/A")")

            if debug, let debugInfo = result.screenDebugInfo {
                print(debugInfo)
            }

            if debug, let paths = result.screenshotPaths {
                for (index, path) in paths.enumerated() {
                    let screenNumber = index + 1
                    let marker = screenNumber == result.activeScreen ? " (active)" : ""
                    print("Screenshot \(screenNumber)\(marker): \(path.path)")
                }
            }

            #if DEBUG
            if let samplePath = result.samplePath {
                print("Sample saved to: \(samplePath.path)")
            }
            #endif

            // Save to database
            let entry = result.toActivityEntry(device: config.device.name)
            let db = try DatabaseHelper()
            try await db.insertActivity(entry)
            print("Saved to database")
        } catch {
            print("Error: \(error.localizedDescription)")
            throw error
        }
    }
}

// MARK: - CLI Tracking Helper

struct CLITrackingHelper {
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
        ZeitConfig.load().schedule.contains(Date())
    }

    /// Whether this tick should track, and why not when it should not.
    ///
    /// A database that cannot be opened reads as "no entry stored", so a
    /// broken database does not silently stop tracking for good.
    func decideTick(now: Date = Date()) async -> TrackingTickDecision {
        let config = ZeitConfig.load()

        return await TrackingTick.decide(
            now: now,
            schedule: config.schedule,
            tracking: config.tracking,
            isTrackingActive: isTrackingActive(),
            isOnBattery: PowerSource.isOnBattery(),
            newestEntry: { try? await DatabaseHelper().newestEntryTimestamp() }
        )
    }
}
