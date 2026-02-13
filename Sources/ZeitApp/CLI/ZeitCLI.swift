import ArgumentParser
import Foundation

/// Root CLI command for Zeit
struct ZeitCLI: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "zeit",
        abstract: "macOS activity tracker",
        version: "0.2.0",
        subcommands: [
            TrackCommand.self,
            ViewCommand.self,
            StatsCommand.self,
            DBCommand.self,
            ServiceCommand.self,
            SetWorkHoursCommand.self,
            DoctorCommand.self,
            VersionCommand.self,
        ]
    )
}

// MARK: - Version Command

struct VersionCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "version",
        abstract: "Show version information"
    )

    func run() throws {
        print("zeit version 0.2.0 (Swift)")
    }
}
