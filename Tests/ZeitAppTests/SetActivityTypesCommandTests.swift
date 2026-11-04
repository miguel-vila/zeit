import ArgumentParser
import Foundation
import GRDB
import Testing

@testable import ZeitApp

/// So a fixed `Z` timestamp lands on the same day key wherever the tests run.
private let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

@Suite
struct SetActivityTypesCommandTests {
    private let existing: [ActivityType] = [
        ActivityType(id: "work_coding", name: "Work Coding", description: "company repos", group: .work),
        ActivityType(
            id: "project_coding", name: "Project Coding", description: "personal repos",
            group: .personalProjects
        ),
        ActivityType(id: "social_media", name: "Social Media", description: "feeds", group: .personal),
    ]

    @Test
    func replacesOnlyTheNamedGroup() throws {
        let replacement = try SetActivityTypesCommand.parseEntries(
            "Meetings: Video calls", group: .work
        )

        let merged = SetActivityTypesCommand.merge([.work: replacement], into: existing)

        #expect(merged.map(\.id) == ["meetings", "project_coding", "social_media"])
    }

    @Test
    func isRepeatableAcrossGroups() throws {
        let work = try SetActivityTypesCommand.parseEntries(
            "Coding: Code in company repos; Meetings: Video calls", group: .work
        )
        let personal = try SetActivityTypesCommand.parseEntries(
            "News: News sites and apps", group: .personal
        )

        let merged = SetActivityTypesCommand.merge(
            [.work: work, .personal: personal], into: existing
        )

        #expect(merged.map(\.id) == ["coding", "meetings", "project_coding", "news"])
        #expect(merged.map(\.group) == [.work, .work, .personalProjects, .personal])
    }

    @Test
    func anEmptyTypeListEmptiesThatGroupAndLeavesTheRest() throws {
        let merged = SetActivityTypesCommand.merge([.personal: []], into: existing)

        #expect(merged.map(\.id) == ["work_coding", "project_coding"])
    }

    @Test
    func parsesNameAndDescriptionIntoAGeneratedID() throws {
        let parsed = try SetActivityTypesCommand.parseEntries(
            "Code Review: Pull requests, diffs and review comments", group: .work
        )

        #expect(parsed.count == 1)
        #expect(parsed[0].id == "code_review")
        #expect(parsed[0].name == "Code Review")
        #expect(parsed[0].description == "Pull requests, diffs and review comments")
        #expect(parsed[0].group == .work)
    }

    @Test
    func rejectsAnEntryWithoutADescription() {
        #expect(throws: ValidationError.self) {
            try SetActivityTypesCommand.parseEntries("Coding", group: .work)
        }
    }

    @Test
    func rejectsTheSameNameTwiceInOneGroup() {
        #expect(throws: ValidationError.self) {
            try SetActivityTypesCommand.parseEntries(
                "Coding: One thing; Coding: Another thing", group: .work
            )
        }
    }
}

@Suite
struct MigratedDatabaseWriteTests {
    /// A database that was created before groups existed, then migrated.
    private func migratedHelper() throws -> (DatabaseHelper, DatabaseQueue) {
        let queue = try DatabaseQueue()
        try ZeitDatabase.migrator.migrate(queue, upTo: "baseline")

        try queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO activity_types
                    (id, name, description, is_work, sort_order, created_at, updated_at)
                    VALUES ('work_coding', 'Work Coding', 'Writing code', 1, 0,
                            '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                    """
            )
        }

        try ZeitDatabase.prepare(queue)
        return (DatabaseHelper(queue: queue), queue)
    }

    @Test
    func anActivityIsStoredAndReadBackWithItsMigratedGroup() async throws {
        let (db, _) = try migratedHelper()

        // What `zeit track` writes once the classifier has produced an activity.
        let entry = ActivityEntry(
            timestamp: "2026-01-01T10:00:00Z",
            activity: .workCoding,
            reasoning: "An IDE with company code",
            description: "Editing a Swift file"
        )
        try await db.insertActivity(entry, attribution: .calendarDay, calendar: utcCalendar)

        let record = try await db.getDayRecord(date: "2026-01-01")
        #expect(record?.activities.map(\.activity) == [.workCoding])

        let types = try await db.getActivityTypes()
        let stats = computeActivityBreakdown(
            from: record?.activities ?? [], activityTypes: types
        )
        #expect(share(of: .work, in: stats) == 100.0)
        #expect(unclassifiedShare(in: stats) == 0.0)
    }

    @Test
    func theClassificationPromptForAMigratedDatabaseListsTheMigratedGroup() async throws {
        let (db, _) = try migratedHelper()

        let prompt = Prompts.activityClassification(
            description: "An IDE with company code",
            activityTypes: try await db.getActivityTypes()
        )

        #expect(prompt.contains("WORK ACTIVITIES:"))
        #expect(prompt.contains("- work_coding: Writing code"))
    }

    @Test
    func seedingDoesNotRunWhenTheMigratedDatabaseAlreadyHasTypes() throws {
        let (_, queue) = try migratedHelper()

        let types = try queue.read { try ZeitDatabase.fetchActivityTypes($0) }
        #expect(types.map(\.id) == ["work_coding"])
    }
}
