import ComposableArchitecture
import Foundation
import GRDB
import Testing
import Yams

@testable import ZeitApp

/// A fixed calendar, so "01:00" is the same moment wherever the tests run.
private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// 2026-01-05 is a Monday, so `day: 5 + n` walks the week from Monday.
private func moment(day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(
        from: DateComponents(year: 2026, month: 1, day: day, hour: hour, minute: minute)
    )!
}

private func timestamp(day: Int, _ hour: Int, _ minute: Int = 0) -> String {
    String(format: "2026-01-%02dT%02d:%02d:00Z", day, hour, minute)
}

/// Which day an entry belongs to, given `tracking.day_start_hour`.
@Suite
struct DayAttributionTests {
    /// The default is the calendar day Zeit used before the hour existed.
    @Test
    func midnightAttributesByTheCalendarDay() {
        let attribution = DayAttribution(dayStartHour: 0)

        #expect(attribution.dayString(for: moment(day: 6, 0, 0), calendar: calendar) == "2026-01-06")
        #expect(attribution.dayString(for: moment(day: 6, 1), calendar: calendar) == "2026-01-06")
        #expect(attribution.dayString(for: moment(day: 6, 23, 59), calendar: calendar) == "2026-01-06")
        #expect(attribution == .calendarDay)
    }

    /// The boundary: 03:59 still belongs to the day that started yesterday at
    /// 04:00, and 04:00 opens the new one.
    @Test
    func aFourAmStartKeepsALateSessionOnTheDayItBegan() {
        let attribution = DayAttribution(dayStartHour: 4)

        #expect(attribution.dayString(for: moment(day: 5, 20), calendar: calendar) == "2026-01-05")
        #expect(attribution.dayString(for: moment(day: 6, 1), calendar: calendar) == "2026-01-05")
        #expect(attribution.dayString(for: moment(day: 6, 3, 59), calendar: calendar) == "2026-01-05")
        #expect(attribution.dayString(for: moment(day: 6, 4), calendar: calendar) == "2026-01-06")
        #expect(attribution.dayString(for: moment(day: 6, 4, 1), calendar: calendar) == "2026-01-06")
    }

    @Test
    func todayAndYesterdayUseTheSameBoundary() {
        let attribution = DayAttribution(dayStartHour: 4)
        let lateNight = moment(day: 6, 1)

        #expect(attribution.today(lateNight, calendar: calendar) == "2026-01-05")
        #expect(attribution.yesterday(lateNight, calendar: calendar) == "2026-01-04")
        #expect(DayAttribution.calendarDay.today(lateNight, calendar: calendar) == "2026-01-06")
        #expect(DayAttribution.calendarDay.yesterday(lateNight, calendar: calendar) == "2026-01-05")
    }

    /// An hour outside a day is not a day start.
    @Test
    func anHourOutsideTheDayIsClampedToOne() {
        #expect(DayAttribution(dayStartHour: -3).dayStartHour == 0)
        #expect(DayAttribution(dayStartHour: 24).dayStartHour == 23)
        #expect(DayAttribution(dayStartHour: 23).dayStartHour == 23)
    }

    /// Attribution is by local wall-clock hour, so the 23-hour day a DST start
    /// makes still has one boundary at 04:00.
    @Test
    func aDstChangeDoesNotMoveTheBoundary() {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!

        // Clocks go forward on 2026-03-08 in New York.
        let lateNight = newYork.date(
            from: DateComponents(year: 2026, month: 3, day: 8, hour: 1)
        )!
        let afterTheStart = newYork.date(
            from: DateComponents(year: 2026, month: 3, day: 8, hour: 5)
        )!
        let attribution = DayAttribution(dayStartHour: 4)

        #expect(attribution.dayString(for: lateNight, calendar: newYork) == "2026-03-07")
        #expect(attribution.dayString(for: afterTheStart, calendar: newYork) == "2026-03-08")
    }
}

/// `tracking.day_start_hour`.
@Suite
struct DayStartHourConfigTests {
    private func tracking(_ yaml: String) throws -> ZeitConfig.TrackingConfig {
        let parsed = try Yams.load(yaml: yaml) as? [String: Any] ?? [:]
        return ZeitConfig.parse(yaml: parsed).tracking
    }

    @Test
    func aConfigWithoutItStartsTheDayAtMidnight() throws {
        #expect(ZeitConfig.defaultTracking.dayStartHour == 0)
        #expect(
            try tracking(
                """
                tracking:
                  schedule: always
                  interval_seconds: 300
                """
            ).dayStartHour == 0
        )
        #expect(try tracking(ZeitConfig.defaultConfigYAML).dayStartHour == 0)
    }

    @Test
    func itIsRead() throws {
        #expect(
            try tracking(
                """
                tracking:
                  schedule: always
                  day_start_hour: 4
                """
            ).dayStartHour == 4
        )
    }

    @Test
    func anHourOutsideTheDayIsClampedOnLoad() throws {
        #expect(try tracking("tracking:\n  day_start_hour: 25").dayStartHour == 23)
        #expect(try tracking("tracking:\n  day_start_hour: -1").dayStartHour == 0)
    }

    @Test
    func itIsWrittenAlongsideTheScheduleAndParsesBackUnchanged() {
        let tracking = ZeitConfig.TrackingConfig(
            intervalSeconds: 300, skipOnBattery: true, dayStartHour: 4
        )
        let written = ZeitConfig.applying(.always, tracking: tracking, to: [:])

        #expect((written["tracking"] as? [String: Any])?["day_start_hour"] as? Int == 4)
        #expect(ZeitConfig.parseTracking(from: written) == tracking)
    }

    /// `zeit schedule` changes the windows only, so a day start set in the file
    /// survives a schedule write.
    @Test
    func aScheduleWriteWithoutTheTrackingBlockLeavesIt() {
        let existing: [String: Any] = ["tracking": ["day_start_hour": 4]]

        let written = ZeitConfig.applying(.always, to: existing)

        #expect((written["tracking"] as? [String: Any])?["day_start_hour"] as? Int == 4)
    }
}

/// The day-start row of the shared schedule editor.
@Suite
struct DayStartHourEditorTests {
    private func tracking(dayStartHour: Int) -> ZeitConfig.TrackingConfig {
        ZeitConfig.TrackingConfig(
            intervalSeconds: 60, skipOnBattery: false, dayStartHour: dayStartHour
        )
    }

    @Test
    func theEditorRoundTripsADayStart() {
        let editor = ScheduleEditorState(schedule: .always, tracking: tracking(dayStartHour: 4))

        #expect(editor.dayStartHour == 4)
        #expect(editor.tracking.dayStartHour == 4)
    }

    @Test
    func loadingASchedulePullsTheDayStartWithIt() {
        var editor = ScheduleEditorState()
        #expect(editor.dayStartHour == 0)

        editor.load(.always, tracking: tracking(dayStartHour: 6))
        #expect(editor.dayStartHour == 6)
    }

    @Test
    func thePickerOffersEveryHourAndNamesMidnight() {
        #expect(ScheduleEditorState.dayStartHourOptions.count == 24)
        #expect(ScheduleEditorState.dayStartHourOptions.first == 0)
        #expect(ScheduleEditorState.dayStartHourOptions.last == 23)
        #expect(ScheduleEditorState.dayStartHourLabel(0) == "Midnight")
        #expect(ScheduleEditorState.dayStartHourLabel(4) != "Midnight")
    }
}

/// Both tabs edit the day start through the same state.
@MainActor
@Suite
struct DayStartHourSettingsTests {
    @Test
    func theScheduleTabEditsAndClampsTheDayStart() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        }
        store.exhaustivity = .off

        await store.send(.scheduleLoaded(.always, ZeitConfig.defaultTracking))

        await store.send(.setDayStartHour(4))
        #expect(store.state.schedule.editor.tracking.dayStartHour == 4)

        await store.send(.setDayStartHour(30))
        #expect(store.state.schedule.editor.tracking.dayStartHour == 23)
    }

    @Test
    func theOnboardingStepEditsTheDayStart() async {
        let store = TestStore(initialState: OtherSettingsFeature.State()) {
            OtherSettingsFeature()
        }
        store.exhaustivity = .off

        await store.send(.scheduleLoaded(.always, ZeitConfig.defaultTracking))

        await store.send(.setDayStartHour(4))
        #expect(store.state.editor.tracking.dayStartHour == 4)
    }
}

/// The day an entry is stored under, and the key it is read back by: one
/// attribution, so storage and reads cannot disagree.
@Suite
struct DayAttributionStorageTests {
    private func database() throws -> DatabaseHelper {
        let queue = try DatabaseQueue()
        try ZeitDatabase.prepare(queue)
        return DatabaseHelper(queue: queue)
    }

    private func entry(day: Int, _ hour: Int, _ minute: Int = 0) -> ActivityEntry {
        ActivityEntry(
            timestamp: timestamp(day: day, hour, minute),
            activity: .workCoding,
            reasoning: nil,
            description: nil
        )
    }

    private func insert(
        _ entries: [ActivityEntry],
        dayStartHour: Int,
        into db: DatabaseHelper
    ) async throws {
        for entry in entries {
            try await db.insertActivity(
                entry,
                attribution: DayAttribution(dayStartHour: dayStartHour),
                calendar: calendar
            )
        }
    }

    @Test
    func withMidnightAnEntryLandsOnItsCalendarDay() async throws {
        let db = try database()

        try await insert([entry(day: 5, 23), entry(day: 6, 1)], dayStartHour: 0, into: db)

        #expect(try await db.getDayRecord(date: "2026-01-05")?.count == 1)
        #expect(try await db.getDayRecord(date: "2026-01-06")?.count == 1)
    }

    /// The point of the setting: an evening session crossing midnight is one
    /// day, not two halves.
    @Test
    func withAFourAmStartAnEveningSessionStaysOneDay() async throws {
        let db = try database()

        try await insert([entry(day: 5, 23), entry(day: 6, 1)], dayStartHour: 4, into: db)

        #expect(try await db.getDayRecord(date: "2026-01-05")?.count == 2)
        #expect(try await db.getDayRecord(date: "2026-01-06") == nil)
    }

    /// Either side of the boundary, written and read with the same attribution.
    @Test
    func theBoundarySplitsTheTwoDays() async throws {
        let db = try database()

        try await insert([entry(day: 6, 3, 59), entry(day: 6, 4)], dayStartHour: 4, into: db)

        let before = try await db.getDayRecord(date: "2026-01-05")
        let after = try await db.getDayRecord(date: "2026-01-06")

        #expect(before?.activities.map(\.timestamp) == [timestamp(day: 6, 3, 59)])
        #expect(after?.activities.map(\.timestamp) == [timestamp(day: 6, 4)])
    }

    /// The write uses the entry's own timestamp, so a classification that
    /// takes a while does not pull an entry over the boundary.
    @Test
    func anEntryIsAttributedByItsTimestampNotByTheWrite() async throws {
        let db = try database()

        try await insert([entry(day: 5, 20)], dayStartHour: 0, into: db)

        #expect(try await db.getDayRecord(date: "2026-01-05")?.count == 1)
    }
}
