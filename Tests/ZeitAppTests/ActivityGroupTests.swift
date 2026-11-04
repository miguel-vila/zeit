import Foundation
import GRDB
import Testing

@testable import ZeitApp

@Suite
struct ActivityTypeMigrationTests {
    /// Build a database at the pre-group schema and fill it with the rows an
    /// existing install would have, including one the user wrote themselves.
    private func legacyDatabase() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try ZeitDatabase.migrator.migrate(queue, upTo: "baseline")

        try queue.write { db in
            let rows: [(String, String, String, Int)] = [
                ("work_coding", "Work Coding", "Writing code, using IDE", 1),
                ("slack", "Slack", "Using Slack for work communication", 1),
                ("professional_development", "Professional Development", "Learning, courses", 0),
                ("personal_ai_use", "Personal AI Use", "AI tools for personal projects", 0),
                ("social_media", "Social Media", "Twitter/X, Instagram", 0),
                // A type the user wrote: Zeit never shipped it, so it must not be
                // remapped by name.
                ("woodworking", "Woodworking", "Plans and cut lists for the shop", 0),
            ]

            for (index, row) in rows.enumerated() {
                try db.execute(
                    sql: """
                        INSERT INTO activity_types
                        (id, name, description, is_work, sort_order, created_at, updated_at)
                        VALUES (?, ?, ?, ?, ?, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                        """,
                    arguments: [row.0, row.1, row.2, row.3, index]
                )
            }
        }

        return queue
    }

    @Test
    func migration_mapsEveryLegacyRowToAGroup() throws {
        let queue = try legacyDatabase()

        try ZeitDatabase.migrator.migrate(queue)

        let types = try queue.read { try ZeitDatabase.fetchActivityTypes($0) }
        let groups = Dictionary(uniqueKeysWithValues: types.map { ($0.id, $0.group) })

        #expect(groups["work_coding"] == .work)
        #expect(groups["slack"] == .work)
        #expect(groups["professional_development"] == .personalProjects)
        #expect(groups["personal_ai_use"] == .personalProjects)
        #expect(groups["social_media"] == .personal)
        // A user-written non-work type lands in personal, not guessed at.
        #expect(groups["woodworking"] == .personal)
    }

    @Test
    func migration_renamesNoID_andKeepsNamesDescriptionsAndOrder() throws {
        let queue = try legacyDatabase()

        try ZeitDatabase.migrator.migrate(queue)

        let types = try queue.read { try ZeitDatabase.fetchActivityTypes($0) }

        #expect(
            types.map(\.id) == [
                "work_coding", "slack", "professional_development",
                "personal_ai_use", "social_media", "woodworking",
            ]
        )
        #expect(types.last?.name == "Woodworking")
        #expect(types.last?.description == "Plans and cut lists for the shop")
    }

    @Test
    func migration_dropsTheIsWorkColumn() throws {
        let queue = try legacyDatabase()

        try ZeitDatabase.migrator.migrate(queue)

        let columns = try queue.read { db in
            try db.columns(in: "activity_types").map(\.name)
        }
        #expect(columns.contains("activity_group"))
        #expect(!columns.contains("is_work"))
    }

    @Test
    func prepare_onAFreshDatabase_seedsTheStarterSetWithGroups() throws {
        let queue = try DatabaseQueue()

        try ZeitDatabase.prepare(queue)

        let types = try queue.read { try ZeitDatabase.fetchActivityTypes($0) }
        #expect(types == ActivityCatalog.starterSet)
        #expect(!types.filter { $0.group == .personalProjects }.isEmpty)
    }

    /// The catalog is the picker's menu, not a set of rows. Seeding it would make
    /// every suggestion a type the user then has to go and unselect.
    @Test
    func prepare_seedsTheStarterSetAndNotTheWholeCatalog() throws {
        let queue = try DatabaseQueue()

        try ZeitDatabase.prepare(queue)

        let ids = try queue.read { try ZeitDatabase.fetchActivityTypes($0) }.map(\.id)
        #expect(ids.count < ActivityCatalog.suggestions.count)

        let notSeeded = ActivityCatalog.suggestions.map(\.id).filter { !ids.contains($0) }
        #expect(!notSeeded.isEmpty)
    }

    @Test
    func prepare_isIdempotent_andDoesNotReseed() throws {
        let queue = try DatabaseQueue()
        try ZeitDatabase.prepare(queue)

        try queue.write { db in
            try db.execute(sql: "DELETE FROM activity_types WHERE id <> 'work_coding'")
        }
        try ZeitDatabase.prepare(queue)

        let types = try queue.read { try ZeitDatabase.fetchActivityTypes($0) }
        #expect(types.map(\.id) == ["work_coding"])
    }
}

@Suite
struct ActivityBreakdownGroupTests {
    private func entry(_ activity: Activity, at minute: Int) -> ActivityEntry {
        ActivityEntry(
            timestamp: String(format: "2026-01-01T10:%02d:00Z", minute),
            activity: activity,
            reasoning: nil,
            description: nil
        )
    }

    private let types: [ActivityType] = [
        ActivityType(id: "work_coding", name: "Work Coding", description: "d", group: .work),
        ActivityType(
            id: "project_coding", name: "Project Coding", description: "d", group: .personalProjects
        ),
        ActivityType(
            id: "social_media", name: "Social Media", description: "d", group: .personal
        ),
    ]

    @Test
    func unknownID_reportsAsUnclassified_neverAsPersonal() {
        let activities = [
            entry(.workCoding, at: 0),
            entry(Activity(rawValue: "project_coding"), at: 1),
            // Unselected type with history: the id is gone from the type table.
            entry(Activity(rawValue: "retired_type"), at: 2),
            entry(.socialMedia, at: 3),
        ]

        let stats = computeActivityBreakdown(from: activities, activityTypes: types)
        let byID = Dictionary(uniqueKeysWithValues: stats.map { ($0.id, $0) })

        #expect(byID["retired_type"]?.group == nil)
        #expect(byID["retired_type"]?.groupLabel == "Unclassified")
        #expect(share(of: .personal, in: stats) == 25.0)
        #expect(unclassifiedShare(in: stats) == 25.0)
    }

    @Test
    func share_sumsOnlyTheGivenGroup() {
        let activities = [
            entry(.workCoding, at: 0),
            entry(.workCoding, at: 1),
            entry(Activity(rawValue: "project_coding"), at: 2),
            entry(.socialMedia, at: 3),
        ]

        let stats = computeActivityBreakdown(from: activities, activityTypes: types)

        #expect(share(of: .work, in: stats) == 50.0)
        #expect(share(of: .personalProjects, in: stats) == 25.0)
        #expect(share(of: .personal, in: stats) == 25.0)
        #expect(unclassifiedShare(in: stats) == 0.0)
    }

    @Test
    func idle_hasNoGroup_andIsNotUnclassified() {
        let activities = [
            entry(.workCoding, at: 0),
            entry(.idle, at: 1),
        ]

        let stats = computeActivityBreakdown(
            from: activities, activityTypes: types, includeIdle: true
        )
        let idle = stats.first { $0.activity == .idle }

        #expect(idle?.group == nil)
        #expect(idle?.groupLabel == "Idle")
        #expect(idleShare(in: stats) == 50.0)
        #expect(unclassifiedShare(in: stats) == 0.0)
    }
}

@Suite
struct ActivityTypeValidatorGroupTests {
    private func type(_ name: String, _ group: ActivityGroup) -> ActivityType {
        ActivityType(
            id: ActivityType.generateID(from: name),
            name: name,
            description: "Something to look for on screen",
            group: group
        )
    }

    @Test
    func aSelectionWithoutWorkTypesIsValid() {
        let types = [type("Project Coding", .personalProjects), type("Social Media", .personal)]

        #expect(
            ActivityTypeValidator.validateAll(types, primaryGroup: .personalProjects).isEmpty
        )
    }

    @Test
    func aSingleTypeIsEnough() {
        #expect(
            ActivityTypeValidator
                .validateAll([type("Work Coding", .work)], primaryGroup: .work)
                .isEmpty
        )
    }

    @Test
    func anEmptySelectionIsRejected() {
        #expect(ActivityTypeValidator.validateAll([], primaryGroup: .work) == [.noTypes])
    }

    @Test
    func namesMustBeUniqueAcrossGroups() {
        let types = [type("Coding", .work), type("Coding", .personalProjects)]

        #expect(
            ActivityTypeValidator
                .validateAll(types, primaryGroup: .work)
                .contains(.duplicateName("Coding"))
        )
    }

    /// The group the day is judged by has to have something in it, or the
    /// menubar number is always zero.
    @Test(arguments: ActivityGroup.allCases)
    func thePrimaryGroupMustHaveAtLeastOneType(primaryGroup: ActivityGroup) {
        let other = ActivityGroup.allCases.first { $0 != primaryGroup }!
        let types = [type("Only One", other)]

        #expect(
            ActivityTypeValidator.validateAll(types, primaryGroup: primaryGroup)
                == [.noTypesInPrimaryGroup(primaryGroup)]
        )
        #expect(
            ActivityTypeValidator
                .validateAll(types + [type("In Primary", primaryGroup)], primaryGroup: primaryGroup)
                .isEmpty
        )
    }

    /// An empty selection is already rejected by `noTypes`; saying the primary
    /// group is empty as well would be the same error twice.
    @Test
    func anEmptySelectionIsNotAlsoReportedAsAnEmptyPrimaryGroup() {
        #expect(
            !ActivityTypeValidator.validateAll([], primaryGroup: .work)
                .contains(.noTypesInPrimaryGroup(.work))
        )
    }
}

@Suite
struct ClassificationPromptTests {
    @Test
    func promptListsOneSectionPerPopulatedGroup() {
        let types = [
            ActivityType(id: "work_coding", name: "Work Coding", description: "company repos", group: .work),
            ActivityType(
                id: "project_coding", name: "Project Coding", description: "personal repos",
                group: .personalProjects
            ),
            ActivityType(id: "social_media", name: "Social Media", description: "feeds", group: .personal),
        ]

        let prompt = Prompts.activityClassification(description: "An IDE", activityTypes: types)

        #expect(prompt.contains("WORK ACTIVITIES:"))
        #expect(prompt.contains("PERSONAL PROJECT ACTIVITIES:"))
        #expect(prompt.contains("PERSONAL ACTIVITIES:"))
        #expect(prompt.contains("- project_coding: personal repos"))
        #expect(!prompt.contains("If unsure between work and personal"))
    }

    @Test
    func anEmptyGroupGetsNoSection() {
        let types = [
            ActivityType(id: "work_coding", name: "Work Coding", description: "company repos", group: .work)
        ]

        let prompt = Prompts.activityClassification(description: "An IDE", activityTypes: types)

        #expect(prompt.contains("WORK ACTIVITIES:"))
        #expect(!prompt.contains("PERSONAL PROJECT ACTIVITIES:"))
        #expect(!prompt.contains("PERSONAL ACTIVITIES:"))
    }
}
