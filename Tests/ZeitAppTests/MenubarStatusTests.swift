import ComposableArchitecture
import Foundation
import Testing

@testable import ZeitApp

/// What the menubar says about tracking, and the two traps a fourth state
/// opens: a status that reports the settings instead of the outcome, and a
/// pause button that reads the status instead of the flag it controls.
@Suite
struct TrackingStateReadingTests {
    private struct Reading: Sendable {
        let decision: TrackingTickDecision
        let state: TrackingState
        let statusMessage: String
        let canToggle: Bool
        let expectsEntries: Bool
    }

    @Test(arguments: [
        Reading(
            decision: .track,
            state: .active,
            statusMessage: "Tracking active",
            canToggle: true,
            expectsEntries: true
        ),
        Reading(
            decision: .tooSoon(elapsed: 20, interval: 60),
            state: .active,
            statusMessage: "Tracking active",
            canToggle: true,
            expectsEntries: true
        ),
        Reading(
            decision: .paused,
            state: .pausedManual,
            statusMessage: "Paused — by you",
            canToggle: true,
            expectsEntries: false
        ),
        Reading(
            decision: .onBattery,
            state: .heldOnBattery,
            statusMessage: "Paused — on battery",
            canToggle: true,
            expectsEntries: true
        ),
    ])
    private func aTickDecisionReadsAsOneState(reading: Reading) {
        let state = TrackingState.from(reading.decision) { "unused" }

        #expect(state == reading.state)
        #expect(state.statusMessage == reading.statusMessage)
        #expect(state.canToggle == reading.canToggle)
        #expect(state.expectsEntries == reading.expectsEntries)
    }

    @Test
    func outsideTheScheduleCarriesTheSchedulesOwnMessage() {
        let state = TrackingState.from(.outsideSchedule) { "Tracking resumes Mon 09:00" }

        #expect(state == .outsideSchedule(message: "Tracking resumes Mon 09:00"))
        #expect(!state.canToggle)
        #expect(!state.expectsEntries)
    }

    @Test
    func theScheduleMessageIsOnlyBuiltForTheStateThatShowsIt() {
        let built = LockIsolated(0)

        _ = TrackingState.from(.onBattery) {
            built.withValue { $0 += 1 }
            return ""
        }

        #expect(built.value == 0)
    }
}

/// The gap between now and the newest stored entry.
@Suite
struct EntryAgeTests {
    private struct Gap: Sendable {
        let seconds: TimeInterval
        let intervalSeconds: Int
        let summary: String
        let isStale: Bool
    }

    @Test(arguments: [
        Gap(seconds: 12, intervalSeconds: 60, summary: "just now", isStale: false),
        Gap(seconds: 61, intervalSeconds: 60, summary: "1m", isStale: false),
        Gap(seconds: 180, intervalSeconds: 60, summary: "3m", isStale: false),
        Gap(seconds: 181, intervalSeconds: 60, summary: "3m", isStale: true),
        Gap(seconds: 3600, intervalSeconds: 60, summary: "1h", isStale: true),
        Gap(seconds: 22_800, intervalSeconds: 60, summary: "6h 20m", isStale: true),
        // A wider cadence has to tolerate a wider gap, or every machine that
        // tracks every ten minutes reads as broken.
        Gap(seconds: 1500, intervalSeconds: 600, summary: "25m", isStale: false),
        Gap(seconds: 1801, intervalSeconds: 600, summary: "30m", isStale: true),
    ])
    private func aGapReadsAgainstTheCadenceThatShouldHaveFilledIt(gap: Gap) {
        let age = EntryAge(seconds: gap.seconds, intervalSeconds: gap.intervalSeconds)

        #expect(age.summary == gap.summary)
        #expect(age.isStale == gap.isStale)
    }

    @Test
    func anEntryInTheFutureIsNoGapAtAll() {
        // A clock change can leave the newest entry ahead of now; that is not
        // a reason to claim the tracker has stopped.
        let age = EntryAge(seconds: -500, intervalSeconds: 60)

        #expect(age.seconds == 0)
        #expect(age.summary == "just now")
        #expect(!age.isStale)
    }
}

@Suite
struct MenubarHoldTests {
    @Test
    func pausingWhileHeldOnBattery_setsTheStopFlag() async {
        let stopped = LockIsolated(false)

        let store = await TestStore(
            initialState: MenubarFeature.State(trackingState: .heldOnBattery)
        ) {
            MenubarFeature()
        } withDependencies: {
            $0.trackingClient.stopTracking = { stopped.setValue(true) }
            $0.trackingClient.isTrackingActive = { true }
            $0.trackingClient.getTrackingState = { .heldOnBattery }
            $0.notificationClient.show = { _, _, _ in }
        }

        await store.send(.toggleTracking)
        await store.receive(\.trackingToggled)

        // Not "resume": the hold never touched the flag, so the button that
        // controls the flag still offers to set it.
        #expect(stopped.value)
    }

    @Test
    func resumingAfterAManualPause_clearsTheStopFlag() async {
        let started = LockIsolated(false)

        let store = await TestStore(
            initialState: MenubarFeature.State(
                trackingState: .pausedManual,
                isPausedByUser: true
            )
        ) {
            MenubarFeature()
        } withDependencies: {
            $0.trackingClient.startTracking = { started.setValue(true) }
            $0.trackingClient.isTrackingActive = { true }
            $0.trackingClient.getTrackingState = { .active }
            $0.notificationClient.show = { _, _, _ in }
        }

        await store.send(.toggleTracking)
        await store.receive(\.trackingToggled) {
            $0.trackingState = .active
            $0.isPausedByUser = false
        }

        #expect(started.value)
    }

    @Test
    func loadedDataCarriesTheNewestEntrysAge() async {
        let now = Date(timeIntervalSince1970: 1_000_000)

        let store = await TestStore(initialState: MenubarFeature.State()) {
            MenubarFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.trackingClient.isTrackingActive = { true }
            $0.trackingClient.getTrackingState = { .heldOnBattery }
            $0.trackingClient.cadenceSeconds = { 60 }
        }

        await store.send(
            .dataLoaded(
                nil, nil, [],
                primaryGroup: .personalProjects,
                newestEntry: now.addingTimeInterval(-22_800)
            )
        ) {
            $0.trackingState = .heldOnBattery
            $0.primaryGroup = .personalProjects
            $0.entryAge = EntryAge(seconds: 22_800, intervalSeconds: 60)
        }

        #expect(store.state.entryAge?.summary == "6h 20m")
        #expect(store.state.entryAge?.isStale == true)
    }

    @Test
    func anEmptyDatabaseHasNoAgeToShow() async {
        let store = await TestStore(initialState: MenubarFeature.State()) {
            MenubarFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_000_000))
            $0.trackingClient.isTrackingActive = { true }
            $0.trackingClient.getTrackingState = { .active }
            $0.trackingClient.cadenceSeconds = { 60 }
        }

        await store.send(
            .dataLoaded(nil, nil, [], primaryGroup: .work, newestEntry: nil)
        ) {
            $0.trackingState = .active
            $0.primaryGroup = .work
        }

        #expect(store.state.entryAge == nil)
    }
}
