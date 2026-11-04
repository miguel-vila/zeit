import Foundation

/// Which day an entry belongs to.
///
/// An entry belongs to the day that started at `dayStartHour` local time. The
/// default, `0`, is the calendar day; `4` keeps a late session on the day it
/// began instead of splitting an evening window across two days.
///
/// Every day key — the `YYYY-MM-DD` a row is written under, and the one a view
/// or the stats read back — comes from here, so storage and reads cannot
/// disagree about where a late entry landed.
struct DayAttribution: Sendable, Equatable {
    /// The local hour a day starts at, 0 to 23.
    let dayStartHour: Int

    /// Midnight: the calendar day, which is what Zeit did before the hour was
    /// configurable.
    static let calendarDay = DayAttribution(dayStartHour: 0)

    /// An hour outside a day is not a day start, so a hand-edited value is
    /// clamped rather than read as a day that never begins. The one place the
    /// bound lives: `ZeitConfig.TrackingConfig` and the schedule editor clamp
    /// through it too.
    static func clamped(dayStartHour hour: Int) -> Int {
        min(max(hour, 0), 23)
    }

    init(dayStartHour: Int) {
        self.dayStartHour = Self.clamped(dayStartHour: dayStartHour)
    }

    init(_ tracking: ZeitConfig.TrackingConfig) {
        self.init(dayStartHour: tracking.dayStartHour)
    }

    /// What this machine is configured to do. Read per call rather than
    /// cached: a tracking run is a whole process, and the menubar has to see
    /// an edited config without a restart.
    static var current: DayAttribution {
        DayAttribution(ZeitConfig.load().tracking)
    }

    // MARK: - Attribution

    /// The day `date` belongs to, as the key rows are stored under.
    func dayString(for date: Date, calendar: Calendar = .current) -> String {
        format(dayStart(for: date, calendar: calendar), calendar: calendar)
    }

    /// The key `days` days away from the one `date` belongs to.
    func dayString(offsetBy days: Int, from date: Date, calendar: Calendar = .current) -> String {
        let start = dayStart(for: date, calendar: calendar)
        let shifted = calendar.date(byAdding: .day, value: days, to: start) ?? start
        return format(shifted, calendar: calendar)
    }

    /// The key for the day `now` falls in.
    func today(_ now: Date = Date(), calendar: Calendar = .current) -> String {
        dayString(for: now, calendar: calendar)
    }

    /// The key for the day before the one `now` falls in.
    func yesterday(_ now: Date = Date(), calendar: Calendar = .current) -> String {
        dayString(offsetBy: -1, from: now, calendar: calendar)
    }

    /// The moment the day `date` belongs to started.
    ///
    /// Decided by comparing the hour rather than by subtracting hours from the
    /// date, so a day that is 23 or 25 hours long across a DST change still
    /// attributes by local wall-clock time.
    func dayStart(for date: Date, calendar: Calendar = .current) -> Date {
        let startOfCalendarDay = calendar.startOfDay(for: date)

        guard dayStartHour > 0,
              calendar.component(.hour, from: date) < dayStartHour
        else {
            return startOfCalendarDay
        }

        return calendar.date(byAdding: .day, value: -1, to: startOfCalendarDay)
            ?? startOfCalendarDay
    }

    // MARK: - Formatting

    /// The calendar and time zone come from `calendar` so an injected one
    /// formats what it computed; the locale is left alone, so a real install
    /// keys its days exactly as it did before.
    private func format(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
