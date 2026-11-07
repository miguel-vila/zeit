import ComposableArchitecture
import Foundation
import GRDB
import Testing

@testable import ZeitApp

/// Onboarding is shown whenever a permission is missing, not only on a first
/// run, and it finishes by writing its list as the whole catalog. So it must
/// only seed from the suggestions on a machine where nobody has chosen types
/// yet — otherwise relaunching the app with a permission denied silently
/// replaces a catalog the user wrote.
@MainActor
@Suite
struct OnboardingSelectionTests {
    private func chosenCatalog() -> [ActivityType] {
        [
            ActivityType(
                id: "work_coding",
                name: "Work Coding",
                description: "my own words about company repos",
                group: .work
            ),
            ActivityType(
                id: "my_own_thing", name: "My Own Thing", description: "mine", group: .work
            ),
        ]
    }

    private func store(
        stored: [ActivityType],
        primaryGroup: ActivityGroup = .work
    ) -> TestStore<ActivityTypesFeature.State, ActivityTypesFeature.Action> {
        TestStore(initialState: ActivityTypesFeature.State(mode: .onboarding)) {
            ActivityTypesFeature()
        } withDependencies: {
            $0.databaseClient.getActivityTypes = { stored }
            $0.classificationClient.primaryGroup = { primaryGroup }
        }
    }

    /// The bug: a catalog somebody chose is kept, not replaced.
    @Test
    func onboardingKeepsASelectionSomebodyChose() async {
        let chosen = chosenCatalog()
        let store = store(stored: chosen)

        await store.send(.task)
        await store.receive(\.typesLoaded) {
            $0.isLoading = false
            $0.primaryGroup = .work
            $0.openedOnAChosenSelection = true
            $0.types = chosen
        }
    }

    /// An edit to the starter set counts as choosing: the text is the user's
    /// even when the list is still the shipped one.
    @Test
    func anEditedStarterSetCountsAsChosen() async {
        var edited = ActivityCatalog.starterSet
        edited[0].description = "my own words"
        let store = store(stored: edited)

        await store.send(.task)
        await store.receive(\.typesLoaded) {
            $0.isLoading = false
            $0.primaryGroup = .work
            $0.openedOnAChosenSelection = true
            $0.types = edited
        }
    }

    /// Changing the goal must not discard a chosen catalog either, since the
    /// same destructive save follows it.
    @Test
    func changingTheGoalKeepsASelectionSomebodyChose() async {
        let chosen = chosenCatalog()
        let store = store(stored: chosen)

        await store.send(.task)
        await store.receive(\.typesLoaded) {
            $0.isLoading = false
            $0.primaryGroup = .work
            $0.openedOnAChosenSelection = true
            $0.types = chosen
        }

        await store.send(.setPrimaryGroup(.personalProjects)) {
            $0.primaryGroup = .personalProjects
        }

        #expect(store.state.types == chosen)
    }

    /// The first run still works: the starter set is what Zeit seeded itself
    /// with for a machine where nobody opened the GUI, so onboarding replaces
    /// it as it always did.
    @Test
    func onboardingStillSeedsOverTheUntouchedStarterSet() async {
        let store = store(stored: ActivityCatalog.starterSet)

        await store.send(.task)
        await store.receive(\.typesLoaded) {
            $0.isLoading = false
            $0.primaryGroup = .work
            $0.types = ActivityCatalog.suggestedSelection(for: .work)
        }
    }

    /// The starter set as seeded, in any row order, is still nobody's choice.
    @Test
    func theStarterSetIsRecognisedWhateverTheRowOrder() {
        #expect(ActivityCatalog.isUnchosen(ActivityCatalog.starterSet.reversed()))
        #expect(!ActivityCatalog.isUnchosen(ActivityCatalog.starterSet.dropLast()))
        #expect(!ActivityCatalog.isUnchosen([]))
    }
}

/// Saving the catalog keeps the rows it already has.
///
/// The editor's list is the whole catalog, so a save has to remove what the
/// user removed — but a type they kept must survive as the same row, or every
/// save rewrites history that other tables point at by id.
@Suite
struct ActivityTypeSaveTests {
    private func database() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try ZeitDatabase.migrator.migrate(queue)
        return queue
    }

    private func rows(_ queue: DatabaseQueue) throws -> [(String, String, String, Int)] {
        try queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, description, created_at, sort_order
                    FROM activity_types ORDER BY sort_order
                    """
            ).map { ($0["id"], $0["description"], $0["created_at"], $0["sort_order"]) }
        }
    }

    private let original = [
        ActivityType(id: "work_coding", name: "Work Coding", description: "repos", group: .work),
        ActivityType(id: "meetings", name: "Meetings", description: "calls", group: .work),
    ]

    @Test
    func aKeptTypeKeepsTheDayItFirstAppeared() throws {
        let queue = try database()
        try queue.write { db in
            try ZeitDatabase.saveActivityTypes(original, into: db)
        }
        let createdAt = try rows(queue).map(\.2)

        var edited = original
        edited[0].description = "my own words"
        try queue.write { db in
            try ZeitDatabase.saveActivityTypes(edited, into: db)
        }

        let after = try rows(queue)
        #expect(after.map(\.1) == ["my own words", "calls"])
        #expect(after.map(\.2) == createdAt)
    }

    /// A type the user removed in the editor is the only way one leaves, so it
    /// still has to go.
    @Test
    func aTypeLeftOutOfTheSaveIsRemoved() throws {
        let queue = try database()
        try queue.write { db in
            try ZeitDatabase.saveActivityTypes(original, into: db)
        }

        try queue.write { db in
            try ZeitDatabase.saveActivityTypes([self.original[1]], into: db)
        }

        #expect(try rows(queue).map(\.0) == ["meetings"])
    }

    @Test
    func aNewTypeIsAdded() throws {
        let queue = try database()
        try queue.write { db in
            try ZeitDatabase.saveActivityTypes(original, into: db)
        }

        let added = ActivityType(
            id: "my_own_thing", name: "My Own Thing", description: "mine", group: .personal
        )
        try queue.write { db in
            try ZeitDatabase.saveActivityTypes(self.original + [added], into: db)
        }

        #expect(try rows(queue).map(\.0) == ["work_coding", "meetings", "my_own_thing"])
    }

    /// `sort_order` is the editor's row order, so reordering the list reorders
    /// the catalog without touching anything else.
    @Test
    func reorderingTheListReordersTheCatalog() throws {
        let queue = try database()
        try queue.write { db in
            try ZeitDatabase.saveActivityTypes(original, into: db)
        }

        try queue.write { db in
            try ZeitDatabase.saveActivityTypes(self.original.reversed(), into: db)
        }

        #expect(try rows(queue).map(\.0) == ["meetings", "work_coding"])
        #expect(try rows(queue).map(\.3) == [0, 1])
    }

    @Test
    func savingAnEmptyCatalogEmptiesIt() throws {
        let queue = try database()
        try queue.write { db in
            try ZeitDatabase.saveActivityTypes(original, into: db)
            try ZeitDatabase.saveActivityTypes([], into: db)
        }

        #expect(try rows(queue).isEmpty)
    }
}
