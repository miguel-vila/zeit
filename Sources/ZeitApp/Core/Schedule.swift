import Foundation

extension ZeitConfig {
    /// When this machine tracks: either always, or inside a list of windows.
    ///
    /// `always` is a case of the same type as `windows` so that "always on, but
    /// only 09:00 to 17:30" cannot be expressed.
    enum ScheduleConfig: Sendable, Equatable {
        case always
        case windows([ScheduleWindow])
    }

    /// One tracking window: a set of days and a start and end time of day.
    ///
    /// When `end <= start` the window ends on the following day, so `days` names
    /// the day the window *starts* on.
    struct ScheduleWindow: Sendable, Equatable {
        let days: Set<Weekday>
        let startHour: Int
        let startMinute: Int
        let endHour: Int
        let endMinute: Int

        init(
            days: Set<Weekday>,
            startHour: Int, startMinute: Int = 0,
            endHour: Int, endMinute: Int = 0
        ) {
            self.days = days
            self.startHour = startHour
            self.startMinute = startMinute
            self.endHour = endHour
            self.endMinute = endMinute
        }

        var startMinuteOfDay: Int { startHour * 60 + startMinute }
        var endMinuteOfDay: Int { endHour * 60 + endMinute }

        /// Whether the window ends on the day after the one `days` names.
        var isOvernight: Bool { endMinuteOfDay <= startMinuteOfDay }

        /// Whether `date` falls inside this window.
        ///
        /// A same-day window matches when the date's weekday is listed and the
        /// time of day is in `[start, end)`. An overnight window matches either
        /// from `start` on a listed day, or before `end` on the day after a
        /// listed one.
        func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
            let components = calendar.dateComponents([.hour, .minute, .weekday], from: date)
            guard let hour = components.hour,
                  let minute = components.minute,
                  let weekdayValue = components.weekday,
                  let today = Weekday(rawValue: weekdayValue)
            else {
                return false
            }

            let minuteOfDay = hour * 60 + minute

            guard isOvernight else {
                return days.contains(today)
                    && minuteOfDay >= startMinuteOfDay
                    && minuteOfDay < endMinuteOfDay
            }

            if days.contains(today), minuteOfDay >= startMinuteOfDay {
                return true
            }

            let previous = Weekday(rawValue: weekdayValue == 1 ? 7 : weekdayValue - 1)
            if let previous, days.contains(previous), minuteOfDay < endMinuteOfDay {
                return true
            }

            return false
        }

        /// "Mon,Tue,Wed,Thu,Fri 9:00-17:30", for status output.
        var summary: String {
            let dayNames = days.sorted().map(\.shortName).joined(separator: ",")
            return "\(dayNames) \(formatTime(startHour, startMinute))-\(formatTime(endHour, endMinute))"
        }

        private func formatTime(_ hour: Int, _ minute: Int) -> String {
            String(format: "%d:%02d", hour, minute)
        }
    }
}

extension ZeitConfig.ScheduleConfig {
    /// Whether `date` is tracked: always, or inside *any* window.
    ///
    /// The union means overlapping windows need no validation.
    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .always:
            return true
        case .windows(let windows):
            return windows.contains { $0.contains(date, calendar: calendar) }
        }
    }

    /// The schedule's shape in one line, for `zeit schedule show` and `doctor`.
    var summary: String {
        switch self {
        case .always:
            return "always"
        case .windows(let windows):
            return windows.map(\.summary).joined(separator: "; ")
        }
    }

    /// "always" or "2 windows": the form alone, without the times.
    var formDescription: String {
        switch self {
        case .always:
            return "always"
        case .windows(let windows):
            return windows.count == 1 ? "1 window" : "\(windows.count) windows"
        }
    }

    /// The status line shown in the menubar and by the CLI.
    func statusMessage(at date: Date = Date(), calendar: Calendar = .current) -> String {
        switch self {
        case .always:
            return "Tracking always on"
        case .windows:
            return contains(date, calendar: calendar)
                ? "Within tracking schedule"
                : "Outside tracking schedule (\(summary))"
        }
    }
}
