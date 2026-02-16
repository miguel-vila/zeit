import ArgumentParser
import Foundation

/// CLI command to set work hours in the configuration.
struct SetWorkHoursCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "set-work-hours",
        abstract: "Set work hour schedule for tracking"
    )

    @Option(name: .long, help: "Work day start time in HH:MM format (e.g. 9:00)")
    var start: String

    @Option(name: .long, help: "Work day end time in HH:MM format (e.g. 17:30)")
    var end: String

    @Option(name: .long, help: "Comma-separated work days (e.g. mon,tue,wed,thu,fri)")
    var days: String?

    func validate() throws {
        guard let startTime = parseTime(start) else {
            throw ValidationError("Start time must be in HH:MM format (e.g. 9:00)")
        }
        guard let endTime = parseTime(end) else {
            throw ValidationError("End time must be in HH:MM format (e.g. 17:30)")
        }
        guard (0...23).contains(startTime.hour) else {
            throw ValidationError("Start hour must be between 0 and 23")
        }
        guard (0...59).contains(startTime.minute) else {
            throw ValidationError("Start minute must be between 0 and 59")
        }
        guard (0...23).contains(endTime.hour) else {
            throw ValidationError("End hour must be between 0 and 23")
        }
        guard (0...59).contains(endTime.minute) else {
            throw ValidationError("End minute must be between 0 and 59")
        }
        let startMinutes = startTime.hour * 60 + startTime.minute
        let endMinutes = endTime.hour * 60 + endTime.minute
        guard startMinutes < endMinutes else {
            throw ValidationError("Start time must be before end time")
        }

        if let days = days {
            let parsed = parseDays(days)
            guard !parsed.isEmpty else {
                throw ValidationError("Invalid days. Use comma-separated short names: sun,mon,tue,wed,thu,fri,sat")
            }
        }
    }

    func run() throws {
        let startTime = parseTime(start)!
        let endTime = parseTime(end)!
        let workDays = days.map { parseDays($0) } ?? ZeitConfig.defaultWorkDays

        try ZeitConfig.saveWorkHours(
            startHour: startTime.hour, startMinute: startTime.minute,
            endHour: endTime.hour, endMinute: endTime.minute,
            workDays: workDays
        )

        let dayNames = workDays.sorted().map(\.shortName).joined(separator: ", ")
        print("Work hours updated: \(formatTime(startTime.hour, startTime.minute)) - \(formatTime(endTime.hour, endTime.minute))")
        print("Work days: \(dayNames)")
    }

    private func parseTime(_ str: String) -> (hour: Int, minute: Int)? {
        let parts = str.split(separator: ":")
        guard let hour = Int(parts.first ?? "") else { return nil }
        let minute = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        return (hour, minute)
    }

    private func parseDays(_ str: String) -> Set<ZeitConfig.Weekday> {
        var result = Set<ZeitConfig.Weekday>()
        for part in str.split(separator: ",") {
            let name = part.trimmingCharacters(in: .whitespaces).lowercased()
            switch name {
            case "sun", "sunday": result.insert(.sunday)
            case "mon", "monday": result.insert(.monday)
            case "tue", "tuesday": result.insert(.tuesday)
            case "wed", "wednesday": result.insert(.wednesday)
            case "thu", "thursday": result.insert(.thursday)
            case "fri", "friday": result.insert(.friday)
            case "sat", "saturday": result.insert(.saturday)
            default: break
            }
        }
        return result
    }

    private func formatTime(_ hour: Int, _ minute: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: date)
    }
}
