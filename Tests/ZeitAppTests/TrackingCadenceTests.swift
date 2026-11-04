import ComposableArchitecture
import Foundation
import GRDB
import Testing
import Yams

@testable import ZeitApp

/// A calendar that puts "Monday 10:00" at the same moment everywhere.
private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// 2026-01-05 is a Monday, so this is a Monday inside the default window.
private let insideWindow = calendar.date(
    from: DateComponents(year: 2026, month: 1, day: 5, hour: 10, minute: 0)
)!

private let weekdays: Set<ZeitConfig.Weekday> = [
    .monday, .tuesday, .wednesday, .thursday, .friday,
]

private let workHours = ZeitConfig.ScheduleConfig.windows([
    ZeitConfig.ScheduleWindow(days: weekdays, startHour: 9, endHour: 17, endMinute: 30)
])

private func cadence(
    _ seconds: Int,
    skipOnBattery: Bool = false,
    dayStartHour: Int = 0
) -> ZeitConfig.TrackingConfig {
    ZeitConfig.TrackingConfig(
        intervalSeconds: seconds,
        skipOnBattery: skipOnBattery,
        dayStartHour: dayStartHour
    )
}

/// launchd fires every 60 seconds whatever the config says, so the tracker
/// decides whether a tick is due.
@Suite
struct TrackingTickTests {
    private func decide(
        now: Date = insideWindow,
        schedule: ZeitConfig.ScheduleConfig = .always,
        tracking: ZeitConfig.TrackingConfig = cadence(60),
        isTrackingActive: Bool = true,
        isOnBattery: Bool = false,
        newestEntryAgo: TimeInterval? = nil
    ) async -> TrackingTickDecision {
        await TrackingTick.decide(
            now: now,
            schedule: schedule,
            tracking: tracking,
            isTrackingActive: isTrackingActive,
            isOnBattery: isOnBattery,
            calendar: calendar,
            newestEntry: { newestEntryAgo.map { now.addingTimeInterval(-$0) } }
        )
    }

    @Test
    func aTickInsideTheIntervalIsSkipped() async {
        let decision = await decide(tracking: cadence(300), newestEntryAgo: 120)

        #expect(decision == .tooSoon(elapsed: 120, interval: 300))
        #expect(!decision.tracks)
    }

    @Test
    func aTickAfterTheIntervalRuns() async {
        #expect(await decide(tracking: cadence(300), newestEntryAgo: 301) == .track)
        #expect(await decide(tracking: cadence(300), newestEntryAgo: 3600) == .track)
    }

    /// The entry is timestamped a moment into the run, so consecutive launchd
    /// ticks land slightly under 60 seconds apart. Without slack the default
    /// cadence would halve itself.
    @Test
    func aTickAFractionEarlyAtTheDefaultCadenceStillRuns() async {
        #expect(await decide(tracking: cadence(60), newestEntryAgo: 58) == .track)
        // Well inside the interval is still a skip.
        #expect(await decide(tracking: cadence(60), newestEntryAgo: 20) != .track)
    }

    @Test
    func theFirstTickOfAnEmptyDatabaseRuns() async {
        #expect(await decide(newestEntryAgo: nil) == .track)
    }

    /// A clock that moved backwards must not hold tracking off until the
    /// interval it can no longer reach has elapsed.
    @Test
    func aNewestEntryInTheFutureRuns() async {
        #expect(await decide(tracking: cadence(300), newestEntryAgo: -3600) == .track)
    }

    @Test
    func aTickOnBatteryIsSkippedOnlyWhenTheGateIsOn() async {
        #expect(
            await decide(tracking: cadence(60, skipOnBattery: true), isOnBattery: true)
                == .onBattery
        )
        #expect(
            await decide(tracking: cadence(60, skipOnBattery: true), isOnBattery: false)
                == .track
        )
        #expect(
            await decide(tracking: cadence(60, skipOnBattery: false), isOnBattery: true)
                == .track
        )
    }

    /// The schedule and the stop flag come first: a due tick outside the
    /// schedule is still not tracked.
    @Test
    func theScheduleAndTheStopFlagOutrankTheCadence() async {
        let saturday = calendar.date(
            from: DateComponents(year: 2026, month: 1, day: 10, hour: 10)
        )!

        #expect(await decide(now: saturday, schedule: workHours) == .outsideSchedule)
        #expect(await decide(schedule: workHours, isTrackingActive: false) == .paused)
    }

    /// Whatever stops a tick has to be loggable, or the tracker log would show
    /// a silent skip.
    @Test
    func everySkippedTickSaysWhy() async {
        let skipped: [TrackingTickDecision] = [
            .outsideSchedule,
            .paused,
            .onBattery,
            .tooSoon(elapsed: 12, interval: 60),
        ]

        for decision in skipped {
            #expect(decision.skipReason != nil)
        }
        #expect(TrackingTickDecision.track.skipReason == nil)
        #expect(
            TrackingTickDecision.tooSoon(elapsed: 12, interval: 60).skipReason
                == "last entry 12s ago, under the 60s cadence"
        )
    }
}

/// `tracking.interval_seconds` and `tracking.skip_on_battery`.
@Suite
struct TrackingConfigParsingTests {
    private func tracking(_ yaml: String) throws -> ZeitConfig.TrackingConfig {
        let parsed = try Yams.load(yaml: yaml) as? [String: Any] ?? [:]
        return ZeitConfig.parse(yaml: parsed).tracking
    }

    @Test
    func aConfigWithoutThemKeepsTheDefaults() throws {
        #expect(
            try tracking(
                """
                tracking:
                  schedule: always
                """
            ) == ZeitConfig.defaultTracking
        )
        #expect(try tracking("models:\n  vision: 'x'") == ZeitConfig.defaultTracking)
        #expect(ZeitConfig.defaultTracking.intervalSeconds == 60)
        #expect(!ZeitConfig.defaultTracking.skipOnBattery)
    }

    @Test
    func bothAreRead() throws {
        let parsed = try tracking(
            """
            tracking:
              schedule: always
              interval_seconds: 300
              skip_on_battery: true
            """
        )

        #expect(parsed == cadence(300, skipOnBattery: true))
    }

    /// A cadence under the launchd tick cannot be honoured, so it is raised
    /// rather than read as "every tick".
    @Test
    func anIntervalBelowTheLaunchdTickIsRaisedToIt() throws {
        #expect(
            try tracking(
                """
                tracking:
                  interval_seconds: 5
                """
            ).intervalSeconds == 60
        )
    }

    @Test
    func theShippedDefaultConfigHoldsTheDefaults() throws {
        #expect(try tracking(ZeitConfig.defaultConfigYAML) == ZeitConfig.defaultTracking)
    }
}

/// The cadence is written next to the schedule, in the same `tracking:` block.
@Suite
struct TrackingConfigWritingTests {
    @Test
    func theCadenceIsWrittenAlongsideTheSchedule() {
        let written = ZeitConfig.applying(
            .always,
            tracking: cadence(300, skipOnBattery: true),
            to: [:]
        )
        let tracking = written["tracking"] as? [String: Any]

        #expect(tracking?["schedule"] as? String == "always")
        #expect(tracking?["interval_seconds"] as? Int == 300)
        #expect(tracking?["skip_on_battery"] as? Bool == true)
    }

    /// `zeit schedule` changes the windows only, so a cadence set in the file
    /// survives a schedule write.
    @Test
    func aScheduleWriteWithoutACadenceLeavesTheExistingOne() {
        let existing: [String: Any] = [
            "tracking": ["interval_seconds": 300, "skip_on_battery": true]
        ]

        let written = ZeitConfig.applying(.always, to: existing)
        let tracking = written["tracking"] as? [String: Any]

        #expect(tracking?["interval_seconds"] as? Int == 300)
        #expect(tracking?["skip_on_battery"] as? Bool == true)
    }

    @Test
    func aWrittenCadenceParsesBackUnchanged() {
        let cadence = cadence(600, skipOnBattery: true)
        let written = ZeitConfig.applying(.always, tracking: cadence, to: [:])

        #expect(ZeitConfig.parseTracking(from: written) == cadence)
    }
}

/// The cadence rows of the shared editor, used by the Schedule settings tab
/// and by onboarding's schedule step.
@Suite
struct ScheduleEditorCadenceTests {
    @Test
    func theEditorRoundTripsACadence() {
        let cadence = cadence(900, skipOnBattery: true)

        #expect(ScheduleEditorState(schedule: .always, tracking: cadence).tracking == cadence)
    }

    @Test
    func theEditorNeverHoldsACadenceUnderTheLaunchdTick() {
        var editor = ScheduleEditorState(schedule: .always, tracking: cadence(10))
        #expect(editor.intervalSeconds == 60)

        editor.intervalSeconds = 1
        #expect(editor.tracking.intervalSeconds == 60)
    }

    /// A hand-edited interval has to be visible in the picker to be changed.
    @Test
    func thePickerOffersThePresetsPlusWhateverTheConfigHolds() {
        let editor = ScheduleEditorState(schedule: .always, tracking: cadence(90))

        #expect(editor.intervalOptions.contains(90))
        #expect(editor.intervalOptions == [60, 90, 120, 300, 600, 900, 1800])
        #expect(
            ScheduleEditorState(schedule: .always, tracking: cadence(60)).intervalOptions
                == ScheduleEditorState.intervalPresets
        )
        #expect(ScheduleEditorState.intervalLabel(300) == "5 min")
        #expect(ScheduleEditorState.intervalLabel(90) == "90s")
    }

    @Test
    func loadingASchedulePullsTheCadenceWithIt() {
        var editor = ScheduleEditorState()
        editor.load(.always, tracking: cadence(1800, skipOnBattery: true))

        #expect(editor.isAlways)
        #expect(editor.intervalSeconds == 1800)
        #expect(editor.skipOnBattery)
    }
}

/// Both tabs edit the cadence through the same state.
@MainActor
@Suite
struct CadenceSettingsTests {
    @Test
    func theScheduleTabEditsAndClampsTheCadence() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        }
        store.exhaustivity = .off

        await store.send(.scheduleLoaded(.always, cadence(60)))

        await store.send(.setInterval(300))
        #expect(store.state.schedule.editor.tracking.intervalSeconds == 300)

        await store.send(.setSkipOnBattery(true))
        #expect(store.state.schedule.editor.tracking.skipOnBattery)

        await store.send(.setInterval(1))
        #expect(store.state.schedule.editor.tracking.intervalSeconds == 60)
    }

    @Test
    func theOnboardingStepEditsTheCadence() async {
        let store = TestStore(initialState: OtherSettingsFeature.State()) {
            OtherSettingsFeature()
        }
        store.exhaustivity = .off

        await store.send(.scheduleLoaded(.always, cadence(60)))

        await store.send(.setInterval(600))
        await store.send(.setSkipOnBattery(true))

        #expect(store.state.editor.tracking == cadence(600, skipOnBattery: true))
    }
}

/// What the cadence gate reads: the timestamp of the newest stored entry.
@Suite
struct NewestEntryTimestampTests {
    private func database() throws -> DatabaseHelper {
        let queue = try DatabaseQueue()
        try ZeitDatabase.prepare(queue)
        return DatabaseHelper(queue: queue)
    }

    private func store(_ timestamps: [String], on date: String, in queue: DatabaseQueue) throws {
        let entries = timestamps.map { timestamp in
            ActivityEntry(
                timestamp: timestamp,
                activity: .workCoding,
                reasoning: nil,
                description: nil
            )
        }
        let json = String(data: try JSONEncoder().encode(entries), encoding: .utf8)!

        try queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO daily_activities (date, activities, created_at, updated_at)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [date, json, "\(date)T00:00:00Z", "\(date)T00:00:00Z"]
            )
        }
    }

    @Test
    func anEmptyDatabaseHasNoNewestEntry() async throws {
        #expect(try await database().newestEntryTimestamp() == nil)
    }

    @Test
    func theNewestEntryOfTheNewestDayIsFound() async throws {
        let queue = try DatabaseQueue()
        try ZeitDatabase.prepare(queue)
        try store(["2026-01-04T10:00:00Z", "2026-01-04T23:00:00Z"], on: "2026-01-04", in: queue)
        try store(["2026-01-05T09:00:00Z", "2026-01-05T09:05:00Z"], on: "2026-01-05", in: queue)

        let newest = try await DatabaseHelper(queue: queue).newestEntryTimestamp()

        #expect(newest == ISO8601DateFormatter().date(from: "2026-01-05T09:05:00Z"))
    }

    /// An entry `zeit track` has just written is what the next tick compares
    /// itself against.
    @Test
    func aJustWrittenEntryIsTheNewestOne() async throws {
        let db = try database()
        let before = Date()

        try await db.insertActivity(
            ActivityEntry(
                timestamp: ISO8601DateFormatter().string(from: before),
                activity: .workCoding,
                reasoning: nil,
                description: nil
            )
        )

        let newest = try await db.newestEntryTimestamp()
        #expect(newest != nil)
        // The format drops sub-second precision, so compare within the second.
        #expect(abs((newest ?? .distantPast).timeIntervalSince(before)) < 1)
    }
}
