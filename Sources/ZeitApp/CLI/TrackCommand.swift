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

        // 1. Check work hours (unless --force or --sample)
        if !shouldForce {
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
        let config = ZeitConfig.load().workHours

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
}
