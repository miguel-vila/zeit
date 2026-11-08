import ArgumentParser
import Foundation

extension Permission: ExpressibleByArgument {}

/// Reports by exit code whether the process holds a permission.
///
/// macOS gives a new Screen Recording grant only to processes that start after
/// it, so a running app cannot see a grant it has just been given — but a
/// process started now can, and inherits the app's TCC identity. The menubar
/// app runs this to tell "not granted" apart from "granted a moment ago".
/// Hidden, because it exists for that one internal use.
struct PermissionCheckCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "permission-check",
        abstract: "Exit 0 when the permission is granted, 1 when it is not",
        shouldDisplay: false
    )

    @Argument(help: "screenRecording or accessibility")
    var permission: Permission

    func run() throws {
        guard permission.isGranted else { throw ExitCode.failure }
    }

    /// Asks a newly started copy of Zeit whether `permission` is granted.
    /// Returns false if the copy cannot be started at all.
    static func ask(_ permission: Permission) -> Bool {
        guard let executable = Bundle.main.executableURL else { return false }

        let process = Process()
        process.executableURL = executable
        process.arguments = [configuration.commandName ?? "permission-check", permission.rawValue]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
