import ArgumentParser
import Foundation

/// CLI command to set work hours in the configuration.
struct SetWorkHoursCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "set-work-hours",
        abstract: "Set work hour schedule for tracking"
    )

    @Option(name: .long, help: "Work day start hour (0-23)")
    var start: Int

    @Option(name: .long, help: "Work day end hour (0-23)")
    var end: Int

    func validate() throws {
        guard (0...23).contains(start) else {
            throw ValidationError("Start hour must be between 0 and 23")
        }
        guard (0...23).contains(end) else {
            throw ValidationError("End hour must be between 0 and 23")
        }
        guard start < end else {
            throw ValidationError("Start hour must be before end hour")
        }
    }

    func run() throws {
        try ZeitConfig.saveWorkHours(startHour: start, endHour: end)
        print("Work hours updated: \(formatHour(start)) - \(formatHour(end))")
    }

    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: date)
    }
}
