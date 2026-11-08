import AppKit
import Dependencies
import DependenciesMacros
import Foundation

// MARK: - Client Interface

/// The two launchd jobs Zeit installs: the tracker, which launchd runs on a
/// timer, and the menubar app, which launchd keeps alive for the login session.
///
/// Two things that used to be one bit are kept apart here. Whether Zeit starts
/// at login is whether its plist exists; whether the app is running now is
/// whether launchd has the job bootstrapped. Quitting changes the second and
/// must leave the first alone.
@DependencyClient
struct LaunchAgentClient: Sendable {
    /// Whether Zeit starts itself at the next login.
    var isLaunchAtLoginEnabled: @Sendable () -> Bool = { false }

    /// Make Zeit start at the next login. Does not start a second copy now.
    var enableLaunchAtLogin: @Sendable () async throws -> Void

    /// Stop Zeit starting at the next login, leaving the running app alone.
    var disableLaunchAtLogin: @Sendable () async throws -> Void

    /// Quit Zeit. launchd restarts the app whenever it dies, so quitting
    /// means taking the job out of this login session and only then
    /// terminating. The plist survives, so Zeit still starts at the next
    /// login, and a copy launchd never started still quits.
    var quitApp: @Sendable () async -> Void

    /// Install both tracker and menubar LaunchAgent plists
    var installServices: @Sendable () async throws -> Void

    /// Load the tracker service via launchctl bootstrap
    var loadTrackerService: @Sendable () async throws -> Void

    /// Reload the tracker service (bootout + bootstrap) to reset launchd throttle
    var reloadTrackerService: @Sendable () async throws -> Void
}

// MARK: - Dependency Registration

extension DependencyValues {
    var launchAgentClient: LaunchAgentClient {
        get { self[LaunchAgentClient.self] }
        set { self[LaunchAgentClient.self] = newValue }
    }
}

// MARK: - Live Implementation

extension LaunchAgentClient: DependencyKey {
    static let liveValue: LaunchAgentClient = {
        let helper = ServiceHelper()

        return LaunchAgentClient(
            isLaunchAtLoginEnabled: {
                helper.plistExists(label: ServiceHelper.menubarLabel)
            },
            enableLaunchAtLogin: {
                try helper.installMenubarService(appPath: Bundle.main.bundlePath)
            },
            disableLaunchAtLogin: {
                try helper.removePlist(label: ServiceHelper.menubarLabel)
            },
            quitApp: {
                if helper.isServiceLoaded(label: ServiceHelper.menubarLabel) {
                    try? helper.unloadService(label: ServiceHelper.menubarLabel)
                }
                await MainActor.run {
                    NSApplication.shared.terminate(nil)
                }
            },
            installServices: {
                try helper.installTrackerService(cliPath: Bundle.main.executablePath ?? "")
                try helper.installMenubarService(appPath: Bundle.main.bundlePath)
            },
            loadTrackerService: {
                try helper.loadService(label: ServiceHelper.trackerLabel)
            },
            reloadTrackerService: {
                try? helper.unloadService(label: ServiceHelper.trackerLabel)
                try helper.loadService(label: ServiceHelper.trackerLabel)
            }
        )
    }()
}
