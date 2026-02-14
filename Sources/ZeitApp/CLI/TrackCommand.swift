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

    @Flag(name: .long, help: "Ignore work hours and stop flag")
    var force: Bool = false

    @Flag(name: .long, help: "Keep screenshots in /tmp and print their paths")
    var debug: Bool = false

    func run() async throws {
        // 1. Check work hours (unless --force)
        if !force {
            let helper = CLITrackingHelper()
            if !helper.isWithinWorkHours() {
                print("Outside work hours, skipping tracking")
                return
            }

            if !helper.isTrackingActive() {
                print("Tracking is paused (stop flag exists)")
                return
            }
        }

        // 2. Check idle
        if let idleTime = IdleDetection.getIdleTimeSeconds(), idleTime > 300 {
            print("System idle for \(Int(idleTime)) seconds, recording idle activity")
            // TODO: Save idle entry to database
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
            let config = ZeitConfig.load()
            let identifier = ActivityIdentifier(
                visionModel: config.models.vision,
                textModel: config.models.text.model,
                textProvider: config.models.text.provider
            )
            let result = try await identifier.identifyCurrentActivity(keepScreenshots: debug, debug: debug)

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

            // Save to database
            let entry = result.toActivityEntry()
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

    func isWithinWorkHours() -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let weekday = calendar.component(.weekday, from: now)

        // Check if it's a weekday (Monday=2 through Friday=6)
        let isWeekday = (2...6).contains(weekday)
        guard isWeekday else { return false }

        // Default work hours: 9-18
        // TODO: Load from config
        return hour >= 9 && hour < 18
    }
}
