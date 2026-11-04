import ArgumentParser
import Foundation

/// `zeit set-work-hours` — kept as an alias for `zeit schedule set` with one
/// window, so existing scripts keep working.
struct SetWorkHoursCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "set-work-hours",
        abstract: "Set a single tracking window (alias for 'schedule set')"
    )

    @Option(name: .long, help: "Window start time in HH:MM format (e.g. 9:00)")
    var start: String

    @Option(name: .long, help: "Window end time in HH:MM format (e.g. 17:30)")
    var end: String

    @Option(name: .long, help: "Comma-separated days (e.g. mon,tue,wed,thu,fri)")
    var days: String?

    func validate() throws {
        guard ScheduleSetCommand.parseTime(start) != nil else {
            throw ValidationError("Start time must be in HH:MM format (e.g. 9:00)")
        }
        guard ScheduleSetCommand.parseTime(end) != nil else {
            throw ValidationError("End time must be in HH:MM format (e.g. 17:30)")
        }

        if let days, ScheduleSetCommand.parseDays(days).isEmpty {
            throw ValidationError(
                "Invalid days. Use comma-separated short names: sun,mon,tue,wed,thu,fri,sat"
            )
        }
    }

    func run() throws {
        let startTime = ScheduleSetCommand.parseTime(start)!
        let endTime = ScheduleSetCommand.parseTime(end)!
        let selectedDays = days.map { ScheduleSetCommand.parseDays($0) } ?? ZeitConfig.defaultScheduleDays

        let window = ZeitConfig.ScheduleWindow(
            days: selectedDays,
            startHour: startTime.hour, startMinute: startTime.minute,
            endHour: endTime.hour, endMinute: endTime.minute
        )
        try ZeitConfig.saveSchedule(.windows([window]))

        print("Schedule updated: 1 window")
        let overnight = window.isOvernight ? "  (ends the following day)" : ""
        print("  \(window.summary)\(overnight)")
    }
}
