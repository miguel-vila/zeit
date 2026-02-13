import AppKit
import Dependencies
import DependenciesMacros
import Foundation

// MARK: - Permission Status

enum PermissionStatus: Equatable, Sendable {
    case notDetermined
    case granted
    case denied
}

// MARK: - App Activation Events

enum AppActivation: Sendable {
    case didBecomeActive
    case willResignActive
}

// MARK: - Settings URLs

private enum SettingsURL {
    static let screenRecording =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    static let accessibility =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
}

// MARK: - Client Interface

/// NOTE: Permissions are checked for the CLI binary that does the actual tracking,
/// NOT for this menubar app. The CLI runs via launchd and needs:
/// - Screen Recording: to capture screenshots
/// - Accessibility: to detect the active window
///
/// This client checks permissions by invoking the CLI with a check flag,
/// or by checking if the CLI binary is in the TCC database.
@DependencyClient
struct PermissionsClient: Sendable {
    /// Check Screen Recording permission status (for the CLI, not this app)
    var screenRecordingStatus: @Sendable () -> PermissionStatus = { .notDetermined }

    /// Check Accessibility permission status (for the CLI, not this app)
    var accessibilityStatus: @Sendable () -> PermissionStatus = { .notDetermined }

    /// Open System Settings to Screen Recording panel
    var openScreenRecordingSettings: @Sendable () async -> Void

    /// Open System Settings to Accessibility panel
    var openAccessibilitySettings: @Sendable () async -> Void

    /// Observe app activation events (for re-checking permissions after Settings)
    var observeAppActivation: @Sendable () -> AsyncStream<AppActivation> = { .never }
}

// MARK: - Dependency Registration

extension DependencyValues {
    var permissionsClient: PermissionsClient {
        get { self[PermissionsClient.self] }
        set { self[PermissionsClient.self] = newValue }
    }
}

// MARK: - Live Implementation

extension PermissionsClient: DependencyKey {
    static let liveValue: PermissionsClient = {
        let observer = AppActivationObserver()
        let helper = PermissionsHelper()

        return PermissionsClient(
            screenRecordingStatus: {
                // Check if CLI has screen recording permission by running it
                // For now, we check the menubar app's permission as a proxy
                // (both need to be granted separately, but this gives user feedback)
                helper.checkScreenRecording()
            },
            accessibilityStatus: {
                // Check if CLI has accessibility permission
                helper.checkAccessibility()
            },
            openScreenRecordingSettings: {
                await MainActor.run {
                    if let url = URL(string: SettingsURL.screenRecording) {
                        NSWorkspace.shared.open(url)
                    }
                }
            },
            openAccessibilitySettings: {
                await MainActor.run {
                    if let url = URL(string: SettingsURL.accessibility) {
                        NSWorkspace.shared.open(url)
                    }
                }
            },
            observeAppActivation: {
                observer.stream
            }
        )
    }()
}

// MARK: - Permissions Helper

private struct PermissionsHelper: Sendable {
    /// Path to the CLI binary (bundled or installed)
    private var cliPath: String? {
        // Check bundled CLI first
        if let bundled = Bundle.main.path(forResource: "zeit", ofType: nil, inDirectory: "zeit") {
            return bundled
        }
        // Check installed CLI
        let installed = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/zeit")
        if FileManager.default.fileExists(atPath: installed.path) {
            return installed.path
        }
        return nil
    }

    /// Run `zeit doctor --json` and parse the results
    func runDoctorCheck() -> DoctorResult? {
        guard let cli = cliPath else { return nil }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: cli)
        task.arguments = ["doctor", "--json"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            // Parse JSON regardless of exit code — doctor exits 1 when any check
            // fails (e.g. Ollama not running), but the JSON still contains valid
            // per-check results we need for permission status.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return try JSONDecoder().decode(DoctorResult.self, from: data)
        } catch {
            return nil
        }
    }

    func checkScreenRecording() -> PermissionStatus {
        guard let result = runDoctorCheck() else {
            return .notDetermined
        }

        if let check = result.checks.first(where: { $0.name.contains("Screen Recording") }) {
            return check.passed ? .granted : .denied
        }

        // Dev mode - permissions check was skipped
        if result.checks.contains(where: { $0.details.contains("Skipped") }) {
            return .notDetermined
        }

        return .notDetermined
    }

    func checkAccessibility() -> PermissionStatus {
        guard let result = runDoctorCheck() else {
            return .notDetermined
        }

        if let check = result.checks.first(where: { $0.name.contains("Accessibility") }) {
            return check.passed ? .granted : .denied
        }

        // Dev mode - permissions check was skipped
        if result.checks.contains(where: { $0.details.contains("Skipped") }) {
            return .notDetermined
        }

        return .notDetermined
    }
}

// MARK: - Doctor Result Model

private struct DoctorResult: Codable {
    let checks: [DoctorCheck]
    let allPassed: Bool

    enum CodingKeys: String, CodingKey {
        case checks
        case allPassed = "all_passed"
    }
}

private struct DoctorCheck: Codable {
    let name: String
    let passed: Bool
    let details: String
}

// MARK: - App Activation Observer

private final class AppActivationObserver: @unchecked Sendable {
    private var continuation: AsyncStream<AppActivation>.Continuation?
    let stream: AsyncStream<AppActivation>

    init() {
        var continuation: AsyncStream<AppActivation>.Continuation?
        self.stream = AsyncStream { continuation = $0 }
        self.continuation = continuation

        // Observe app activation
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.continuation?.yield(.didBecomeActive)
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.continuation?.yield(.willResignActive)
        }
    }
}

// MARK: - Convenience

extension PermissionsClient {
    /// Check if all required permissions are granted
    func allPermissionsGranted() -> Bool {
        screenRecordingStatus() == .granted && accessibilityStatus() == .granted
    }
}
