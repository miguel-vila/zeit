import ComposableArchitecture
import Testing

@testable import ZeitApp

@Suite
struct MenubarFeatureTests {
    @Test
    func toggleTracking_whenActive_stopsTracking() async {
        let store = await TestStore(
            initialState: MenubarFeature.State(trackingState: .active)
        ) {
            MenubarFeature()
        } withDependencies: {
            $0.trackingClient.stopTracking = {}
            $0.trackingClient.getTrackingState = { .pausedManual }
            $0.notificationClient.show = { _, _, _ in }
        }

        await store.send(.toggleTracking)

        await store.receive(.trackingToggled(.success(()))) {
            $0.trackingState = .pausedManual
        }
    }

    @Test
    func toggleTracking_outsideWorkHours_showsNotification() async {
        let store = await TestStore(
            initialState: MenubarFeature.State(
                trackingState: .outsideWorkHours(message: "After work hours")
            )
        ) {
            MenubarFeature()
        } withDependencies: {
            $0.notificationClient.show = { _, _, _ in }
        }

        await store.send(.toggleTracking)
        // No state change - just shows notification
    }
}

@Suite
struct ActivityStatTests {
    @Test
    func computeActivityBreakdown_calculatesPercentages() {
        let activities = [
            ActivityEntry(timestamp: "2025-01-01T10:00:00", activity: .workCoding, reasoning: nil),
            ActivityEntry(timestamp: "2025-01-01T10:01:00", activity: .workCoding, reasoning: nil),
            ActivityEntry(timestamp: "2025-01-01T10:02:00", activity: .slack, reasoning: nil),
            ActivityEntry(timestamp: "2025-01-01T10:03:00", activity: .personalBrowsing, reasoning: nil),
        ]

        let stats = computeActivityBreakdown(from: activities)

        #expect(stats.count == 3)
        #expect(stats[0].activity == .workCoding)
        #expect(stats[0].percentage == 50.0)
        #expect(stats[0].count == 2)
    }

    @Test
    func workPercentage_sumsWorkActivities() {
        let stats = [
            ActivityStat(activity: .workCoding, count: 5, percentage: 50.0),
            ActivityStat(activity: .slack, count: 2, percentage: 20.0),
            ActivityStat(activity: .personalBrowsing, count: 3, percentage: 30.0),
        ]

        let result = workPercentage(from: stats)

        #expect(result == 70.0)  // workCoding + slack
    }
}
