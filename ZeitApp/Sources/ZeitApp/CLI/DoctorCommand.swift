import ArgumentParser
import Foundation

/// System diagnostics command
struct DoctorCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check system configuration"
    )

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() async throws {
        var checks: [Check] = []

        // Model checks (on-device MLX models)
        checks.append(await checkLocalModel(MLXModelManager.visionModel))
        checks.append(await checkLocalModel(MLXModelManager.textModel))

        // Permission checks
        checks.append(checkScreenRecordingPermission())
        checks.append(checkAccessibilityPermission())

        // Data directory checks
        checks.append(checkDataDirectory())
        checks.append(checkDatabaseFile())
        checks.append(checkLogDirectory())

        // Service checks
        let helper = ServiceHelper()
        checks.append(Check(
            name: "Tracker LaunchAgent",
            passed: helper.plistExists(label: ServiceHelper.trackerLabel),
            details: helper.plistExists(label: ServiceHelper.trackerLabel)
                ? helper.plistPath(label: ServiceHelper.trackerLabel).path
                : "Not installed"
        ))
        checks.append(Check(
            name: "Menubar LaunchAgent",
            passed: helper.plistExists(label: ServiceHelper.menubarLabel),
            details: helper.plistExists(label: ServiceHelper.menubarLabel)
                ? helper.plistPath(label: ServiceHelper.menubarLabel).path
                : "Not installed"
        ))
        checks.append(Check(
            name: "Tracker service",
            passed: helper.isServiceLoaded(label: ServiceHelper.trackerLabel),
            details: helper.isServiceLoaded(label: ServiceHelper.trackerLabel) ? "Running" : "Not running"
        ))
        checks.append(Check(
            name: "Menubar service",
            passed: helper.isServiceLoaded(label: ServiceHelper.menubarLabel),
            details: helper.isServiceLoaded(label: ServiceHelper.menubarLabel) ? "Running" : "Not running"
        ))

        let allPassed = checks.allSatisfy { $0.passed }

        if json {
            try printJSON(checks: checks, allPassed: allPassed)
        } else {
            printTable(checks: checks, allPassed: allPassed)
        }

        if !allPassed {
            throw ExitCode(1)
        }
    }

    // MARK: - Check Functions

    private func checkLocalModel(_ model: MLXModelInfo) async -> Check {
        let isDownloaded = await MLXModelManager.shared.isModelDownloaded(model: model)
        return Check(
            name: "Model: \(model.displayName)",
            passed: isDownloaded,
            details: isDownloaded
                ? "Downloaded (\(model.huggingFaceID))"
                : "Not downloaded - use the app's onboarding or download via the menubar"
        )
    }

    private func checkScreenRecordingPermission() -> Check {
        let hasPermission = Permissions.checkScreenRecording()
        return Check(
            name: "Permission: Screen Recording",
            passed: hasPermission,
            details: hasPermission ? "Granted" : "Open: x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )
    }

    private func checkAccessibilityPermission() -> Check {
        let hasPermission = Permissions.checkAccessibility()
        return Check(
            name: "Permission: Accessibility",
            passed: hasPermission,
            details: hasPermission ? "Granted" : "Open: x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }

    private func checkDataDirectory() -> Check {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/zeit")
        let exists = FileManager.default.fileExists(atPath: path.path)
        return Check(
            name: "Data directory",
            passed: exists,
            details: exists ? path.path : "Not found"
        )
    }

    private func checkDatabaseFile() -> Check {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/zeit/zeit.db")
        let exists = FileManager.default.fileExists(atPath: path.path)
        return Check(
            name: "Database file",
            passed: exists,
            details: exists ? path.path : "Not found"
        )
    }

    private func checkLogDirectory() -> Check {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/zeit")
        let exists = FileManager.default.fileExists(atPath: path.path)
        return Check(
            name: "Log directory",
            passed: exists,
            details: exists ? path.path : "Not found"
        )
    }

    // MARK: - Output

    private func printJSON(checks: [Check], allPassed: Bool) throws {
        struct Output: Encodable {
            let checks: [Check]
            let allPassed: Bool

            enum CodingKeys: String, CodingKey {
                case checks
                case allPassed = "all_passed"
            }
        }

        let output = Output(checks: checks, allPassed: allPassed)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(output)
        print(String(data: data, encoding: .utf8)!)
    }

    private func printTable(checks: [Check], allPassed: Bool) {
        print("Zeit System Check")
        print("=" .repeated(60))
        print("")

        for check in checks {
            let status = check.passed ? "✓" : "✗"
            let statusColor = check.passed ? "" : ""  // Could add ANSI colors
            print("\(status) \(check.name)")
            print("    \(check.details)")
        }

        print("")
        if allPassed {
            print("All checks passed!")
        } else {
            print("Some checks failed. See details above.")
        }
    }
}

// MARK: - Check Model

struct Check: Encodable {
    let name: String
    let passed: Bool
    let details: String
}
