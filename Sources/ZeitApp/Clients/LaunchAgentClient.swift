import Dependencies
import DependenciesMacros
import Foundation

// MARK: - Service Identifiers

private enum ServiceIdentifier {
    static let tracker = "co.invariante.zeit"
    static let menubar = "co.invariante.zeit.menubar"
}

// MARK: - Client Interface

@DependencyClient
struct LaunchAgentClient: Sendable {
    /// Check if the menubar service is loaded
    var isMenubarServiceLoaded: @Sendable () -> Bool = { false }

    /// Check if the tracker service is loaded
    var isTrackerServiceLoaded: @Sendable () -> Bool = { false }

    /// Load the menubar service
    var loadMenubarService: @Sendable () async throws -> Void

    /// Unload the menubar service
    var unloadMenubarService: @Sendable () async throws -> Void

    /// Restart the tracker service
    var restartTrackerService: @Sendable () async throws -> Void

    /// Install both tracker and menubar LaunchAgent plists
    var installServices: @Sendable () async throws -> Void

    /// Load the tracker service via launchctl bootstrap
    var loadTrackerService: @Sendable () async throws -> Void
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
        let helper = LaunchAgentHelper()

        return LaunchAgentClient(
            isMenubarServiceLoaded: {
                helper.isServiceLoaded(ServiceIdentifier.menubar)
            },
            isTrackerServiceLoaded: {
                helper.isServiceLoaded(ServiceIdentifier.tracker)
            },
            loadMenubarService: {
                try await helper.loadService(ServiceIdentifier.menubar)
            },
            unloadMenubarService: {
                try await helper.unloadService(ServiceIdentifier.menubar)
            },
            restartTrackerService: {
                try await helper.restartService(ServiceIdentifier.tracker)
            },
            installServices: {
                let serviceHelper = ServiceHelper()
                let cliPath = Bundle.main.executablePath ?? ""
                let appPath = Bundle.main.bundlePath
                try serviceHelper.installTrackerService(cliPath: cliPath)
                try serviceHelper.installMenubarService(appPath: appPath)
            },
            loadTrackerService: {
                let serviceHelper = ServiceHelper()
                try serviceHelper.loadService(label: ServiceHelper.trackerLabel)
            }
        )
    }()
}

// MARK: - Helper

private struct LaunchAgentHelper: Sendable {
    private static let launchAgentsDir = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents")

    func isServiceLoaded(_ identifier: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["list", identifier]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    func loadService(_ identifier: String) async throws {
        let plistPath = Self.launchAgentsDir
            .appendingPathComponent("\(identifier).plist")

        guard FileManager.default.fileExists(atPath: plistPath.path) else {
            throw LaunchAgentError.plistNotFound(identifier)
        }

        try await runLaunchctl(["load", plistPath.path])
    }

    func unloadService(_ identifier: String) async throws {
        let plistPath = Self.launchAgentsDir
            .appendingPathComponent("\(identifier).plist")

        if FileManager.default.fileExists(atPath: plistPath.path) {
            try await runLaunchctl(["unload", plistPath.path])
        }
    }

    func restartService(_ identifier: String) async throws {
        // Kick-start triggers the service immediately
        try await runLaunchctl(["kickstart", "-k", "gui/\(getuid())/\(identifier)"])
    }

    private func runLaunchctl(_ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            task.arguments = arguments

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            task.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(
                        throwing: LaunchAgentError.commandFailed(arguments.joined(separator: " "), message)
                    )
                }
            }

            do {
                try task.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - Errors

enum LaunchAgentError: LocalizedError {
    case plistNotFound(String)
    case commandFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .plistNotFound(let identifier):
            return "LaunchAgent plist not found for \(identifier)"
        case .commandFailed(let command, let message):
            return "launchctl \(command) failed: \(message)"
        }
    }
}
