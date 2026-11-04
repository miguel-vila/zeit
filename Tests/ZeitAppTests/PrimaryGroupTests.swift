import ComposableArchitecture
import Foundation
import Testing
import Yams

@testable import ZeitApp

/// `classification.primary_group` is the one classification setting a machine
/// stores. Parsing is exercised through `ZeitConfig.parse(yaml:)` so the tests
/// never touch the config file on disk.
@Suite
struct PrimaryGroupConfigTests {
    private func config(_ yaml: String) throws -> ZeitConfig {
        let parsed = try Yams.load(yaml: yaml) as? [String: Any] ?? [:]
        return ZeitConfig.parse(yaml: parsed)
    }

    @Test(arguments: ActivityGroup.allCases)
    func primaryGroupIsReadFromTheConfig(group: ActivityGroup) throws {
        let parsed = try config(
            """
            classification:
              primary_group: '\(group.rawValue)'
            """
        )

        #expect(parsed.classification.primaryGroup == group)
    }

    /// An existing install has no `classification:` block.
    @Test
    func aConfigWithoutAClassificationBlockDefaultsToWork() throws {
        let parsed = try config(
            """
            work_hours:
              start_hour: 9
              end_hour: 17
            """
        )

        #expect(parsed.classification.primaryGroup == .work)
        #expect(ZeitConfig.defaultClassification.primaryGroup == .work)
    }

    /// A typo must not take the rest of the config down with it.
    @Test
    func anUnrecognisedGroupFallsBackToTheDefaultAndKeepsTheRest() throws {
        let parsed = try config(
            """
            classification:
              primary_group: 'side_projects'

            models:
              vision: 'qwen3-vl:8b'
            """
        )

        #expect(parsed.classification.primaryGroup == .work)
        #expect(parsed.models.vision == "qwen3-vl:8b")
    }

    /// The config `ensureSetup()` writes on a fresh install has to parse back to
    /// the documented default rather than fall through to it.
    @Test
    func theShippedDefaultConfigNamesThePrimaryGroup() throws {
        let yaml = try Yams.load(yaml: ZeitConfig.defaultConfigYAML) as? [String: Any]
        let classification = yaml?["classification"] as? [String: Any]

        #expect(classification?["primary_group"] as? String == "work")
        #expect(
            try config(ZeitConfig.defaultConfigYAML).classification.primaryGroup == .work
        )
    }
}

/// The asymmetry between the groups lives in the onboarding copy only: the enum
/// stays flat and settings offers all three.
@Suite
struct PrimaryGroupGoalTests {
    @Test
    func onboardingOffersTwoAnswers() {
        #expect(ActivityGroup.goals == [.work, .personalProjects])
    }

    /// `personal` is the residual group: measured against, never for.
    @Test
    func personalIsNotOfferedAsAGoal() {
        #expect(!ActivityGroup.goals.contains(.personal))
        #expect(ActivityGroup.allCases.contains(.personal))
    }

    @Test
    func everyGroupHasALabelForBothTheQuestionAndTheMenubar() {
        for group in ActivityGroup.allCases {
            #expect(!group.goalLabel.isEmpty)
            #expect(!group.goalDetail.isEmpty)
            #expect(!group.shortName.isEmpty)
        }
    }
}

/// The menubar's number is the primary group's share of non-idle tracked
/// entries, and the popover shows every group against it.
@MainActor
@Suite
struct MenubarPrimaryGroupTests {
    private let types: [ActivityType] = [
        ActivityType(id: "work_coding", name: "Work Coding", description: "d", group: .work),
        ActivityType(
            id: "project_coding", name: "Project Coding", description: "d",
            group: .personalProjects
        ),
        ActivityType(
            id: "social_media", name: "Social Media", description: "d", group: .personal
        ),
    ]

    private func entry(_ id: String, at minute: Int) -> ActivityEntry {
        ActivityEntry(
            timestamp: String(format: "2026-01-01T10:%02d:00Z", minute),
            activity: Activity(rawValue: id),
            reasoning: nil,
            description: nil
        )
    }

    /// Four work entries, three project entries, one personal entry and one idle
    /// entry: 50/37.5/12.5 over the eight that are not idle. No two groups share
    /// a share, so the breakdown's order is deterministic.
    private var record: DayRecord {
        DayRecord(
            date: "2026-01-01",
            activities: (0..<4).map { entry("work_coding", at: $0) }
                + (4..<7).map { entry("project_coding", at: $0) }
                + [entry("social_media", at: 7), entry("idle", at: 8)]
        )
    }

    private func store(
        _ primaryGroup: ActivityGroup
    ) async -> TestStore<MenubarFeature.State, MenubarFeature.Action> {
        let store = TestStore(initialState: MenubarFeature.State()) {
            MenubarFeature()
        } withDependencies: {
            $0.trackingClient.getTrackingState = { .active }
        }

        let record = self.record
        let types = self.types

        await store.send(.dataLoaded(record, nil, types, primaryGroup: primaryGroup)) {
            $0.trackingState = .active
            $0.primaryGroup = primaryGroup
            $0.totalActivities = record.count
            $0.todayStats = computeActivityBreakdown(
                from: record.activities, activityTypes: types
            )
        }

        return store
    }

    @Test(
        arguments: [
            (ActivityGroup.work, 50.0),
            (ActivityGroup.personalProjects, 37.5),
            (ActivityGroup.personal, 12.5),
        ]
    )
    func theIconShowsThePrimaryGroupsShare(
        primaryGroup: ActivityGroup, expected: Double
    ) async {
        let store = await self.store(primaryGroup)

        #expect(store.state.primaryGroupPercentage == expected)
        #expect(store.state.primaryGroup == primaryGroup)
    }

    /// Idle is tracked but is not a group, so it must not dilute the number.
    @Test
    func theGroupSharesAddUpWithoutIdle() async {
        let store = await self.store(.work)
        let total = ActivityGroup.allCases
            .reduce(0.0) { $0 + store.state.percentage(of: $1) }

        #expect(total == 100.0)
        #expect(store.state.unclassifiedPercentage == 0.0)
        // The idle entry is still counted as tracked activity.
        #expect(store.state.totalActivities == 9)
    }

    /// The popover lists every group, not only the primary one.
    @Test
    func everyGroupHasAShareToShow() async {
        let store = await self.store(.personalProjects)

        #expect(store.state.percentage(of: .work) == 50.0)
        #expect(store.state.percentage(of: .personalProjects) == 37.5)
        #expect(store.state.percentage(of: .personal) == 12.5)
    }

    /// An unselected type with history is Unclassified, so the popover gains a
    /// row rather than folding it into a group it was never labelled with.
    @Test
    func anUnconfiguredTypeShowsAsUnclassified() async {
        let store = TestStore(initialState: MenubarFeature.State()) {
            MenubarFeature()
        } withDependencies: {
            $0.trackingClient.getTrackingState = { .active }
        }

        let record = DayRecord(
            date: "2026-01-01",
            activities: (0..<3).map { entry("work_coding", at: $0) }
                + [entry("retired_type", at: 3)]
        )
        let types = self.types

        await store.send(.dataLoaded(record, nil, types, primaryGroup: .work)) {
            $0.trackingState = .active
            $0.primaryGroup = .work
            $0.totalActivities = 4
            $0.todayStats = computeActivityBreakdown(
                from: record.activities, activityTypes: types
            )
        }

        #expect(store.state.primaryGroupPercentage == 75.0)
        #expect(store.state.unclassifiedPercentage == 25.0)
    }

    /// With no entries at all the number is zero rather than stale.
    @Test
    func aDayWithNoRecordHasNoShares() async {
        var initial = MenubarFeature.State()
        initial.todayStats = [
            ActivityStat(activity: .workCoding, count: 1, percentage: 100.0, group: .work)
        ]
        initial.totalActivities = 1

        let store = TestStore(initialState: initial) {
            MenubarFeature()
        } withDependencies: {
            $0.trackingClient.getTrackingState = { .pausedManual }
        }

        await store.send(.dataLoaded(nil, nil, types, primaryGroup: .work)) {
            $0.totalActivities = 0
            $0.todayStats = []
        }

        #expect(store.state.primaryGroupPercentage == 0.0)
    }
}
