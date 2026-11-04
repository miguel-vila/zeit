import ArgumentParser
import Foundation

/// `zeit schedule` — show the tracking schedule, or set it to always or to a
/// list of windows.
struct ScheduleCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "schedule",
        abstract: "Show or set when this machine tracks",
        subcommands: [
            ScheduleShowCommand.self,
            ScheduleAlwaysCommand.self,
            ScheduleSetCommand.self,
        ],
        defaultSubcommand: ScheduleShowCommand.self
    )
}

// MARK: - Show

struct ScheduleShowCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Print the tracking schedule and whether now is inside it"
    )

    func run() throws {
        let schedule = ZeitConfig.load().schedule

        switch schedule {
        case .always:
            print("Schedule: always")
        case .windows(let windows):
            print("Schedule: \(schedule.formDescription)")
            for window in windows {
                let overnight = window.isOvernight ? "  (ends the following day)" : ""
                print("  \(window.summary)\(overnight)")
            }
        }

        let now = Date()
        print("Now: \(schedule.contains(now) ? "✓ tracking" : "✗ not tracking")")
    }
}

// MARK: - Always

struct ScheduleAlwaysCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "always",
        abstract: "Track at all times"
    )

    func run() throws {
        try ZeitConfig.saveSchedule(.always)
        print("Schedule updated: always")
    }
}

// MARK: - Set

/// `--days`, `--from` and `--to` are repeatable and paired by position, one
/// triple per window.
struct ScheduleSetCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Track inside a list of windows",
        discussion: """
            Each window needs a --days, a --from and a --to value, in that order:

              zeit schedule set --days mon-fri --from 09:00 --to 13:00 \\
                                --days mon-fri --from 14:00 --to 18:00

            --days takes comma-separated short names and ranges: mon,wed or
            mon-fri or sat-sun. A window whose --to is at or before its --from
            ends the following day, so --days names the day it starts on.

            A moment is tracked when any window contains it, so windows may
            overlap.
            """
    )

    @Option(
        name: .long,
        parsing: .singleValue,
        help: "Days the window starts on, e.g. mon-fri or sat,sun. Repeatable"
    )
    var days: [String] = []

    @Option(
        name: .long,
        parsing: .singleValue,
        help: "Window start time in HH:MM format. Repeatable"
    )
    var from: [String] = []

    @Option(
        name: .long,
        parsing: .singleValue,
        help: "Window end time in HH:MM format. Repeatable"
    )
    var to: [String] = []

    func validate() throws {
        // Parse eagerly so a malformed window fails before anything is written.
        _ = try Self.parseWindows(days: days, from: from, to: to)
    }

    func run() throws {
        let windows = try Self.parseWindows(days: days, from: from, to: to)
        try ZeitConfig.saveSchedule(.windows(windows))

        print("Schedule updated: \(windows.count == 1 ? "1 window" : "\(windows.count) windows")")
        for window in windows {
            let overnight = window.isOvernight ? "  (ends the following day)" : ""
            print("  \(window.summary)\(overnight)")
        }
    }

    /// Build the windows from the repeated flags, which are paired by position.
    static func parseWindows(
        days: [String],
        from: [String],
        to: [String]
    ) throws -> [ZeitConfig.ScheduleWindow] {
        guard !days.isEmpty || !from.isEmpty || !to.isEmpty else {
            throw ValidationError("At least one window (--days, --from, --to) must be specified")
        }

        guard days.count == from.count, days.count == to.count else {
            throw ValidationError(
                "Each window needs one --days, one --from and one --to "
                    + "(got \(days.count) --days, \(from.count) --from and \(to.count) --to)"
            )
        }

        return try zip(days, zip(from, to)).map { days, times in
            let parsedDays = parseDays(days)
            guard !parsedDays.isEmpty else {
                throw ValidationError(
                    "Invalid days '\(days)'. Use comma-separated short names or ranges: mon,wed or mon-fri"
                )
            }

            guard let start = parseTime(times.0) else {
                throw ValidationError("Start time '\(times.0)' must be in HH:MM format (e.g. 9:00)")
            }
            guard let end = parseTime(times.1) else {
                throw ValidationError("End time '\(times.1)' must be in HH:MM format (e.g. 17:30)")
            }

            return ZeitConfig.ScheduleWindow(
                days: parsedDays,
                startHour: start.hour, startMinute: start.minute,
                endHour: end.hour, endMinute: end.minute
            )
        }
    }

    // MARK: - Parsing

    /// "mon,wed", "mon-fri" and "sat-sun" all name day sets. A range wraps the
    /// week, so "sat-sun" is Saturday and Sunday rather than nothing.
    static func parseDays(_ str: String) -> Set<ZeitConfig.Weekday> {
        var result = Set<ZeitConfig.Weekday>()

        for part in str.split(separator: ",") {
            let token = part.trimmingCharacters(in: .whitespaces).lowercased()
            let bounds = token.split(separator: "-", maxSplits: 1)

            if bounds.count == 2 {
                guard let first = parseDay(String(bounds[0])),
                      let last = parseDay(String(bounds[1]))
                else {
                    return []
                }

                var day = first
                result.insert(day)
                while day != last {
                    day = ZeitConfig.Weekday(rawValue: day.rawValue == 7 ? 1 : day.rawValue + 1)!
                    result.insert(day)
                }
            } else if let day = parseDay(token) {
                result.insert(day)
            } else {
                return []
            }
        }

        return result
    }

    static func parseDay(_ name: String) -> ZeitConfig.Weekday? {
        switch name.trimmingCharacters(in: .whitespaces).lowercased() {
        case "sun", "sunday": return .sunday
        case "mon", "monday": return .monday
        case "tue", "tues", "tuesday": return .tuesday
        case "wed", "wednesday": return .wednesday
        case "thu", "thur", "thurs", "thursday": return .thursday
        case "fri", "friday": return .friday
        case "sat", "saturday": return .saturday
        default: return nil
        }
    }

    static func parseTime(_ str: String) -> (hour: Int, minute: Int)? {
        let parts = str.split(separator: ":")
        guard parts.count <= 2,
              let hour = Int(parts.first ?? ""),
              (0...23).contains(hour)
        else {
            return nil
        }

        guard parts.count == 2 else { return (hour, 0) }
        guard let minute = Int(parts[1]), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }
}
