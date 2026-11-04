import ComposableArchitecture
import Foundation
import Testing
import Yams

@testable import ZeitApp

/// A fixed calendar so a test's "Monday 10:00" is the same moment everywhere.
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

private let monday = 5
private let tuesday = 6
private let friday = 9
private let saturday = 10
private let sunday = 11

private func window(
    _ days: Set<ZeitConfig.Weekday>,
    _ startHour: Int, _ startMinute: Int,
    _ endHour: Int, _ endMinute: Int
) -> ZeitConfig.ScheduleWindow {
    ZeitConfig.ScheduleWindow(
        days: days,
        startHour: startHour, startMinute: startMinute,
        endHour: endHour, endMinute: endMinute
    )
}

private let weekdays: Set<ZeitConfig.Weekday> = [
    .monday, .tuesday, .wednesday, .thursday, .friday,
]

/// A moment is tracked when *any* window contains it. Overlaps and overnight
/// spans are valid by definition, so these are the cases the union has to get
/// right.
@Suite
struct ScheduleContainmentTests {
    @Test
    func aSingleWindowTracksItsOwnHoursOnItsOwnDays() {
        let schedule = ZeitConfig.ScheduleConfig.windows([window(weekdays, 9, 0, 17, 30)])

        #expect(!schedule.contains(moment(day: monday, 8, 59), calendar: calendar))
        #expect(schedule.contains(moment(day: monday, 9, 0), calendar: calendar))
        #expect(schedule.contains(moment(day: monday, 17, 29), calendar: calendar))
        // The end is exclusive, so two back-to-back windows cannot double count.
        #expect(!schedule.contains(moment(day: monday, 17, 30), calendar: calendar))
    }

    @Test
    func aDayTheWindowDoesNotListIsNotTracked() {
        let schedule = ZeitConfig.ScheduleConfig.windows([window(weekdays, 9, 0, 17, 30)])

        #expect(!schedule.contains(moment(day: saturday, 10, 0), calendar: calendar))
        #expect(!schedule.contains(moment(day: sunday, 10, 0), calendar: calendar))
    }

    @Test
    func severalWindowsLeaveTheGapBetweenThemUntracked() {
        let schedule = ZeitConfig.ScheduleConfig.windows([
            window(weekdays, 9, 0, 13, 0),
            window(weekdays, 14, 0, 18, 0),
        ])

        #expect(schedule.contains(moment(day: tuesday, 12, 59), calendar: calendar))
        #expect(!schedule.contains(moment(day: tuesday, 13, 30), calendar: calendar))
        #expect(schedule.contains(moment(day: tuesday, 14, 0), calendar: calendar))
        #expect(schedule.contains(moment(day: friday, 17, 59), calendar: calendar))
        #expect(!schedule.contains(moment(day: friday, 18, 0), calendar: calendar))
    }

    /// Overlapping windows need no validation: the union is still a union.
    @Test
    func overlappingWindowsAreTheirUnion() {
        let schedule = ZeitConfig.ScheduleConfig.windows([
            window(weekdays, 9, 0, 13, 0),
            window([.monday], 12, 0, 20, 0),
        ])

        #expect(schedule.contains(moment(day: monday, 12, 30), calendar: calendar))
        #expect(schedule.contains(moment(day: monday, 19, 0), calendar: calendar))
        // Tuesday only has the first window.
        #expect(!schedule.contains(moment(day: tuesday, 19, 0), calendar: calendar))
    }

    /// `to <= from` ends the window on the following day, and `days` names the
    /// day it starts on.
    @Test
    func anOvernightWindowRunsIntoTheNextDay() {
        let schedule = ZeitConfig.ScheduleConfig.windows([window([.friday], 20, 0, 1, 0)])

        #expect(!schedule.contains(moment(day: friday, 19, 59), calendar: calendar))
        #expect(schedule.contains(moment(day: friday, 20, 0), calendar: calendar))
        #expect(schedule.contains(moment(day: friday, 23, 59), calendar: calendar))
        // Saturday 00:30 belongs to Friday's window; 01:00 is past its end.
        #expect(schedule.contains(moment(day: saturday, 0, 30), calendar: calendar))
        #expect(!schedule.contains(moment(day: saturday, 1, 0), calendar: calendar))
        // Saturday is not a listed start day, so Saturday evening is untracked.
        #expect(!schedule.contains(moment(day: saturday, 21, 0), calendar: calendar))
    }

    /// Sunday into Monday: the previous day wraps across the week boundary.
    @Test
    func anOvernightWindowWrapsFromSundayIntoMonday() {
        let schedule = ZeitConfig.ScheduleConfig.windows([window([.sunday], 22, 0, 2, 0)])

        #expect(schedule.contains(moment(day: sunday, 22, 30), calendar: calendar))
        #expect(schedule.contains(moment(day: sunday + 1, 1, 30), calendar: calendar))
        #expect(!schedule.contains(moment(day: sunday + 1, 2, 30), calendar: calendar))
    }

    /// `to == from` is overnight too, which makes it a 24 hour window.
    @Test
    func aWindowThatEndsWhenItStartsCoversAFullDay() {
        let schedule = ZeitConfig.ScheduleConfig.windows([window([.monday], 9, 0, 9, 0)])

        #expect(!schedule.contains(moment(day: monday, 8, 59), calendar: calendar))
        #expect(schedule.contains(moment(day: monday, 9, 0), calendar: calendar))
        #expect(schedule.contains(moment(day: tuesday, 8, 59), calendar: calendar))
        #expect(!schedule.contains(moment(day: tuesday, 9, 0), calendar: calendar))
    }

    @Test
    func alwaysTracksEveryMoment() {
        let schedule = ZeitConfig.ScheduleConfig.always

        #expect(schedule.contains(moment(day: monday, 3, 0), calendar: calendar))
        #expect(schedule.contains(moment(day: saturday, 23, 59), calendar: calendar))
        #expect(schedule.summary == "always")
        #expect(schedule.formDescription == "always")
    }

    @Test
    func theStatusMessageNamesTheWindowsOnlyWhenOutsideThem() {
        let schedule = ZeitConfig.ScheduleConfig.windows([window(weekdays, 9, 0, 17, 30)])

        #expect(
            schedule.statusMessage(at: moment(day: monday, 10, 0), calendar: calendar)
                == "Within tracking schedule"
        )
        #expect(
            schedule.statusMessage(at: moment(day: saturday, 10, 0), calendar: calendar)
                == "Outside tracking schedule (Mon,Tue,Wed,Thu,Fri 9:00-17:30)"
        )
    }
}

/// `tracking.schedule` is parsed through `ZeitConfig.parse(yaml:)` so the tests
/// never touch the config file on disk.
@Suite
struct ScheduleConfigParsingTests {
    private func schedule(_ yaml: String) throws -> ZeitConfig.ScheduleConfig {
        let parsed = try Yams.load(yaml: yaml) as? [String: Any] ?? [:]
        return ZeitConfig.parse(yaml: parsed).schedule
    }

    @Test
    func alwaysIsAValueOfTheSameField() throws {
        #expect(
            try schedule(
                """
                tracking:
                  schedule: always
                """
            ) == .always
        )
    }

    @Test
    func aWindowListIsReadInOrder() throws {
        let parsed = try schedule(
            """
            tracking:
              schedule:
                windows:
                  - days: ['mon', 'tue', 'wed', 'thu', 'fri']
                    from: '09:00'
                    to: '13:00'
                  - days: ['mon', 'tue', 'wed', 'thu', 'fri']
                    from: '14:00'
                    to: '18:00'
            """
        )

        #expect(
            parsed
                == .windows([
                    window(weekdays, 9, 0, 13, 0),
                    window(weekdays, 14, 0, 18, 0),
                ])
        )
    }

    /// A silent "never track" is worse than a loud fallback.
    @Test
    func anEmptyWindowListIsRejectedAndKeepsTheDefault() throws {
        #expect(
            try schedule(
                """
                tracking:
                  schedule:
                    windows: []
                """
            ) == ZeitConfig.defaultSchedule
        )
    }

    @Test
    func aWindowMissingItsTimesIsDropped() throws {
        let parsed = try schedule(
            """
            tracking:
              schedule:
                windows:
                  - days: ['mon']
                  - days: ['sat', 'sun']
                    from: '10:00'
                    to: '12:00'
            """
        )

        #expect(parsed == .windows([window([.saturday, .sunday], 10, 0, 12, 0)]))
    }

    @Test
    func anUnrecognisedScheduleKeepsTheDefaultAndTheRestOfTheConfig() throws {
        let parsed = try Yams.load(
            yaml: """
                tracking:
                  schedule: weekdays-only

                models:
                  vision: 'qwen3-vl:8b'
                """
        ) as? [String: Any] ?? [:]
        let config = ZeitConfig.parse(yaml: parsed)

        #expect(config.schedule == ZeitConfig.defaultSchedule)
        #expect(config.models.vision == "qwen3-vl:8b")
    }

    /// An existing install has a `work_hours:` block and no `tracking:` block.
    @Test
    func aLegacyWorkHoursBlockLoadsAsOneWindow() throws {
        let parsed = try schedule(
            """
            work_hours:
              start_hour: 8
              start_minute: 30
              end_hour: 16
              end_minute: 0
              work_days: ['mon', 'wed', 'fri']
            """
        )

        #expect(parsed == .windows([window([.monday, .wednesday, .friday], 8, 30, 16, 0)]))
    }

    /// The other legacy hour format, with the times as strings.
    @Test
    func aLegacyWorkHoursBlockWithStringTimesLoadsTheSameWay() throws {
        let parsed = try schedule(
            """
            work_hours:
              work_start_hour: '09:15'
              work_end_hour: '17:45'
            """
        )

        #expect(parsed == .windows([window(ZeitConfig.defaultScheduleDays, 9, 15, 17, 45)]))
    }

    @Test
    func aConfigWithNoScheduleAtAllGetsTheDefault() throws {
        #expect(
            try schedule(
                """
                models:
                  vision: 'qwen3-vl:4b'
                """
            ) == ZeitConfig.defaultSchedule
        )
    }

    /// The config `ensureSetup()` writes on a fresh install has to parse back to
    /// the documented default rather than fall through to it.
    @Test
    func theShippedDefaultConfigNamesTheSchedule() throws {
        let yaml = try Yams.load(yaml: ZeitConfig.defaultConfigYAML) as? [String: Any]
        let tracking = yaml?["tracking"] as? [String: Any]

        #expect(tracking?["schedule"] != nil)
        #expect(yaml?["work_hours"] == nil)
        #expect(try schedule(ZeitConfig.defaultConfigYAML) == ZeitConfig.defaultSchedule)
    }
}

/// Only the new shape is written, and a legacy block does not survive a write.
@Suite
struct ScheduleConfigWritingTests {
    private func written(
        _ schedule: ZeitConfig.ScheduleConfig,
        into yaml: [String: Any] = [:]
    ) -> [String: Any] {
        ZeitConfig.applying(schedule, to: yaml)
    }

    @Test
    func alwaysIsWrittenAsTheStringAlways() {
        let tracking = written(.always)["tracking"] as? [String: Any]

        #expect(tracking?["schedule"] as? String == "always")
    }

    @Test
    func windowsAreWrittenAsDaysFromAndTo() {
        let tracking = written(
            .windows([window([.saturday, .sunday], 20, 0, 1, 30)])
        )["tracking"] as? [String: Any]
        let schedule = tracking?["schedule"] as? [String: Any]
        let windows = schedule?["windows"] as? [[String: Any]]

        #expect(windows?.count == 1)
        #expect(windows?.first?["days"] as? [String] == ["sun", "sat"])
        #expect(windows?.first?["from"] as? String == "20:00")
        #expect(windows?.first?["to"] as? String == "01:30")
    }

    @Test
    func aLegacyWorkHoursBlockIsNeverWrittenBack() {
        let legacy: [String: Any] = [
            "work_hours": ["start_hour": 9, "end_hour": 17],
            "classification": ["primary_group": "work"],
        ]

        let written = written(.always, into: legacy)

        #expect(written["work_hours"] == nil)
        #expect(written["classification"] as? [String: Any] != nil)
    }

    /// A round trip has to come back as the same schedule, or the GUI would
    /// re-open on something the user did not choose.
    @Test
    func aWrittenScheduleParsesBackUnchanged() {
        let schedule = ZeitConfig.ScheduleConfig.windows([
            window(weekdays, 9, 0, 13, 0),
            window([.saturday], 22, 0, 2, 0),
        ])

        #expect(ZeitConfig.parseSchedule(from: written(schedule)) == schedule)
    }
}

/// `zeit schedule set` takes one `--days`, `--from` and `--to` per window.
@Suite
struct ScheduleCommandParsingTests {
    @Test
    func daysAcceptCommaListsAndRanges() {
        #expect(ScheduleSetCommand.parseDays("mon-fri") == weekdays)
        #expect(ScheduleSetCommand.parseDays("mon,wed") == [.monday, .wednesday])
        #expect(ScheduleSetCommand.parseDays("Mon, Tue") == [.monday, .tuesday])
        // A range may wrap the end of the week.
        #expect(ScheduleSetCommand.parseDays("sat-sun") == [.saturday, .sunday])
        #expect(ScheduleSetCommand.parseDays("fri-mon") == [.friday, .saturday, .sunday, .monday])
    }

    @Test
    func anUnknownDayNameYieldsNoDays() {
        #expect(ScheduleSetCommand.parseDays("moonday").isEmpty)
        #expect(ScheduleSetCommand.parseDays("mon-moonday").isEmpty)
        #expect(ScheduleSetCommand.parseDays("").isEmpty)
    }

    @Test
    func timesParseAsHHMM() {
        #expect(ScheduleSetCommand.parseTime("09:00").map(\.hour) == 9)
        #expect(ScheduleSetCommand.parseTime("9:05").map(\.minute) == 5)
        #expect(ScheduleSetCommand.parseTime("17").map(\.minute) == 0)
        #expect(ScheduleSetCommand.parseTime("24:00") == nil)
        #expect(ScheduleSetCommand.parseTime("09:60") == nil)
        #expect(ScheduleSetCommand.parseTime("nine") == nil)
        #expect(ScheduleSetCommand.parseTime("9:00:00") == nil)
    }

    @Test
    func aWindowCountMismatchIsRejected() throws {
        #expect(throws: (any Error).self) {
            try ScheduleSetCommand.parseWindows(
                days: ["mon-fri", "sat"], from: ["09:00"], to: ["13:00"]
            )
        }
    }

    @Test
    func aWindowWithNoDaysIsRejected() throws {
        #expect(throws: (any Error).self) {
            try ScheduleSetCommand.parseWindows(
                days: ["someday"], from: ["09:00"], to: ["13:00"]
            )
        }
    }

    @Test
    func aMalformedTimeIsRejected() throws {
        #expect(throws: (any Error).self) {
            try ScheduleSetCommand.parseWindows(
                days: ["mon"], from: ["09:00"], to: ["half past six"]
            )
        }
    }

    @Test
    func noWindowAtAllIsRejected() throws {
        #expect(throws: (any Error).self) {
            try ScheduleSetCommand.parseWindows(days: [], from: [], to: [])
        }
    }

    /// The repeated flags are paired by position, one triple per window.
    @Test
    func repeatedWindowFlagsBuildOneWindowEach() throws {
        let windows = try ScheduleSetCommand.parseWindows(
            days: ["mon-fri", "sat-sun"],
            from: ["09:00", "20:00"],
            to: ["13:00", "01:00"]
        )

        #expect(
            windows == [
                window(weekdays, 9, 0, 13, 0),
                window([.saturday, .sunday], 20, 0, 1, 0),
            ]
        )
        #expect(windows[1].isOvernight)
    }

    /// `zeit set-work-hours` is the same write with one window, through the old
    /// flag names.
    @Test
    func theSetWorkHoursAliasIsOneWindow() throws {
        let command = try SetWorkHoursCommand.parse([
            "--start", "09:00", "--end", "17:30", "--days", "mon,tue",
        ])

        #expect(command.start == "09:00")
        #expect(ScheduleSetCommand.parseDays(command.days ?? "") == [.monday, .tuesday])
    }
}

/// The form and the window rows the onboarding step and the Schedule tab edit.
@Suite
struct ScheduleEditorStateTests {
    @Test
    func anEditorLoadedWithAlwaysStillHasARowToEdit() {
        var editor = ScheduleEditorState(schedule: .always)

        #expect(editor.isAlways)
        #expect(editor.schedule == .always)

        // Switching back to Windows must not leave an empty list.
        editor.isAlways = false
        #expect(editor.schedule == ZeitConfig.defaultSchedule)
    }

    @Test
    func addingAndRemovingWindows() {
        var editor = ScheduleEditorState(
            schedule: .windows([window(weekdays, 9, 0, 13, 0)])
        )

        editor.addWindow()
        #expect(editor.windows.count == 2)

        let added = editor.windows[1]
        editor.removeWindow(id: added.id)
        #expect(editor.windows.map(\.id) == [editor.windows[0].id])

        // The last row stays: an empty list is not a schedule.
        editor.removeWindow(id: editor.windows[0].id)
        #expect(editor.windows.count == 1)
    }

    @Test
    func editingARowKeepsItsPlaceAndRejectsAnEmptyDaySet() {
        var editor = ScheduleEditorState(
            schedule: .windows([
                window(weekdays, 9, 0, 13, 0),
                window([.saturday], 20, 0, 1, 0),
            ])
        )

        var second = editor.windows[1]
        second.endHour = 2
        editor.update(second)

        #expect(editor.windows[1].endHour == 2)
        #expect(editor.windows[0].startHour == 9)

        var emptied = editor.windows[1]
        emptied.days = []
        editor.update(emptied)

        #expect(editor.windows[1].days == [.saturday])
    }

    @Test
    func theEditorRoundTripsAWindowSchedule() {
        let schedule = ZeitConfig.ScheduleConfig.windows([
            window(weekdays, 9, 0, 13, 0),
            window(weekdays, 14, 0, 18, 0),
        ])

        #expect(ScheduleEditorState(schedule: schedule).schedule == schedule)
    }
}

/// The Schedule settings tab drives the shared editor and saves the result.
@MainActor
@Suite
struct ScheduleSettingsTabTests {
    @Test
    func theTabLoadsEditsAndKeepsTheFormChoice() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        }
        store.exhaustivity = .off

        await store.send(
            .scheduleLoaded(
                .windows([window(weekdays, 9, 0, 13, 0)]),
                ZeitConfig.defaultTracking
            )
        )
        #expect(!store.state.schedule.editor.isAlways)
        #expect(store.state.schedule.editor.windows.count == 1)

        await store.send(.addWindow)
        #expect(store.state.schedule.editor.windows.count == 2)

        var second = store.state.schedule.editor.windows[1]
        second.days = [.saturday, .sunday]
        await store.send(.changeWindow(second))
        #expect(store.state.schedule.editor.windows[1].days == [.saturday, .sunday])

        await store.send(.removeWindow(second.id))
        #expect(store.state.schedule.editor.windows.count == 1)

        await store.send(.setAlways(true))
        #expect(store.state.schedule.editor.schedule == .always)
    }
}
