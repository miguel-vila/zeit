import ArgumentParser
import Foundation

/// LaunchAgent service management commands
struct ServiceCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "service",
        abstract: "Manage tracking services",
        subcommands: [
            ServiceStatusCommand.self,
            ServiceStartCommand.self,
            ServiceStopCommand.self,
            ServiceInstallCommand.self,
            ServiceUninstallCommand.self,
            ServiceRestartCommand.self,
        ]
    )
}

// MARK: - Status

struct ServiceStatusCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show service status"
    )

    func run() throws {
        let helper = ServiceHelper()

        print("Zeit Service Status")
        print("==================")
        print("")

        // Tracker service
        let trackerLoaded = helper.isServiceLoaded(label: ServiceHelper.trackerLabel)
        let trackerPlistExists = helper.plistExists(label: ServiceHelper.trackerLabel)
        print("Tracker Service:")
        print("  Plist: \(trackerPlistExists ? "✓ Installed" : "✗ Not installed")")
        print("  Status: \(trackerLoaded ? "✓ Running" : "✗ Not running")")

        // Menubar service
        let menubarLoaded = helper.isServiceLoaded(label: ServiceHelper.menubarLabel)
        let menubarPlistExists = helper.plistExists(label: ServiceHelper.menubarLabel)
        print("")
        print("Menubar Service:")
        print("  Plist: \(menubarPlistExists ? "✓ Installed" : "✗ Not installed")")
        print("  Status: \(menubarLoaded ? "✓ Running" : "✗ Not running")")

        // Tracking state
        let tracking = CLITrackingHelper()
        print("")
        print("Tracking:")
        print("  Active: \(tracking.isTrackingActive() ? "✓ Yes" : "✗ Paused")")
        print("  Schedule: \(tracking.isWithinSchedule() ? "✓ Within" : "✗ Outside")")
    }
}

// MARK: - Start

struct ServiceStartCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Resume tracking (remove stop flag)"
    )

    func run() throws {
        let stopFlagPath = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/zeit/.zeit_stop")

        if FileManager.default.fileExists(atPath: stopFlagPath.path) {
            try FileManager.default.removeItem(at: stopFlagPath)
            print("Tracking resumed")
        } else {
            print("Tracking was not paused")
        }
    }
}

// MARK: - Stop

struct ServiceStopCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Pause tracking (create stop flag)"
    )

    func run() throws {
        let stopFlagPath = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/zeit/.zeit_stop")

        FileManager.default.createFile(atPath: stopFlagPath.path, contents: nil)
        print("Tracking paused")
    }
}

// MARK: - Install

struct ServiceInstallCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install LaunchAgent services"
    )

    @Option(name: .long, help: "Path to CLI binary")
    var cli: String?

    @Option(name: .long, help: "Path to menubar app")
    var app: String?

    func run() throws {
        let helper = ServiceHelper()

        // Determine paths
        let cliPath = cli ?? Bundle.main.executablePath ?? ""
        let appPath = app ?? Bundle.main.bundlePath

        print("Installing services...")
        print("  CLI: \(cliPath)")
        print("  App: \(appPath)")

        // Create tracker plist
        try helper.installTrackerService(cliPath: cliPath)
        print("✓ Tracker service installed")

        // Create menubar plist
        try helper.installMenubarService(appPath: appPath)
        print("✓ Menubar service installed")

        print("")
        print("Services installed. They will start on next login.")
        print("To start now, run: zeit service restart")
    }
}

// MARK: - Uninstall

struct ServiceUninstallCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Remove LaunchAgent services"
    )

    func run() throws {
        let helper = ServiceHelper()

        // Unload and remove tracker
        try? helper.unloadService(label: ServiceHelper.trackerLabel)
        try? helper.removePlist(label: ServiceHelper.trackerLabel)
        print("✓ Tracker service removed")

        // Unload and remove menubar
        try? helper.unloadService(label: ServiceHelper.menubarLabel)
        try? helper.removePlist(label: ServiceHelper.menubarLabel)
        print("✓ Menubar service removed")

        print("")
        print("All services removed.")
    }
}

// MARK: - Restart

struct ServiceRestartCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "restart",
        abstract: "Restart tracking service"
    )

    func run() throws {
        let helper = ServiceHelper()

        print("Restarting tracker service...")
        try helper.restartService(label: ServiceHelper.trackerLabel)
        print("✓ Tracker service restarted")
    }
}

// MARK: - Service Helper

struct ServiceHelper {
    static let trackerLabel = "co.invariante.zeit"
    static let menubarLabel = "co.invariante.zeit.menubar"

    /// Where the plists are written. Only a test passes anything but the
    /// default, which is the one directory launchd reads at login.
    let launchAgentsDir: URL

    init(
        launchAgentsDir: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
    ) {
        self.launchAgentsDir = launchAgentsDir
    }

    func plistPath(label: String) -> URL {
        launchAgentsDir.appendingPathComponent("\(label).plist")
    }

    func plistExists(label: String) -> Bool {
        FileManager.default.fileExists(atPath: plistPath(label: label).path)
    }

    func isServiceLoaded(label: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["list", label]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    func loadService(label: String) throws {
        let uid = getuid()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["bootstrap", "gui/\(uid)", plistPath(label: label).path]

        try task.run()
        task.waitUntilExit()

        if task.terminationStatus != 0 {
            throw ServiceError.loadFailed(label)
        }
    }

    func unloadService(label: String) throws {
        let uid = getuid()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["bootout", "gui/\(uid)/\(label)"]

        try task.run()
        task.waitUntilExit()
    }

    func restartService(label: String) throws {
        let uid = getuid()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["kickstart", "-k", "gui/\(uid)/\(label)"]

        try task.run()
        task.waitUntilExit()

        if task.terminationStatus != 0 {
            throw ServiceError.restartFailed(label)
        }
    }

    func removePlist(label: String) throws {
        let path = plistPath(label: label)
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
    }

    /// The plist tick is fixed at 60 seconds and does not follow
    /// `tracking.interval_seconds`: a tracking run compares the newest stored
    /// entry against the configured cadence and decides whether the tick is
    /// due, so changing the cadence needs no reinstall and the plist cannot
    /// disagree with the config.
    func installTrackerService(cliPath: String) throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(Self.trackerLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(cliPath)</string>
                <string>track</string>
            </array>
            <key>StartInterval</key>
            <integer>60</integer>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
            <key>StandardOutPath</key>
            <string>\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Logs/zeit/tracker.out.log</string>
            <key>StandardErrorPath</key>
            <string>\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Logs/zeit/tracker.err.log</string>
            <key>EnvironmentVariables</key>
            <dict>
                <key>HOME</key>
                <string>\(FileManager.default.homeDirectoryForCurrentUser.path)</string>
                <key>PATH</key>
                <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
            </dict>
            <key>WorkingDirectory</key>
            <string>\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/share/zeit</string>
        </dict>
        </plist>
        """

        // Ensure LaunchAgents directory exists
        try FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)

        // Ensure logs directory exists
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/zeit")
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        // Write plist
        try plist.write(to: plistPath(label: Self.trackerLabel), atomically: true, encoding: .utf8)
    }

    /// launchd runs the executable inside the bundle rather than `open`, so
    /// that the menubar app is launchd's own child and `KeepAlive` can bring
    /// it back when something else kills it — System Settings after a
    /// permission grant, or a crash. `open` exits as soon as it has launched
    /// the app, which left launchd with nothing to watch.
    ///
    /// `KeepAlive` is unconditional, so the user's Quit has to take the job
    /// out of the session; see `LaunchAgentClient.stopMenubarService`.
    func installMenubarService(appPath: String) throws {
        guard let executable = Bundle(path: appPath)?.executableURL?.path else {
            throw ServiceError.noExecutable(appPath)
        }

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(Self.menubarLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(executable)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardOutPath</key>
            <string>\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Logs/zeit/menubar.out.log</string>
            <key>StandardErrorPath</key>
            <string>\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Logs/zeit/menubar.err.log</string>
            <key>ProcessType</key>
            <string>Interactive</string>
        </dict>
        </plist>
        """

        try FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
        try plist.write(to: plistPath(label: Self.menubarLabel), atomically: true, encoding: .utf8)
    }
}

enum ServiceError: LocalizedError {
    case loadFailed(String)
    case restartFailed(String)
    case noExecutable(String)

    var errorDescription: String? {
        switch self {
        case .loadFailed(let label):
            return "Failed to load service: \(label)"
        case .restartFailed(let label):
            return "Failed to restart service: \(label)"
        case .noExecutable(let path):
            return "No app bundle with an executable at: \(path)"
        }
    }
}
