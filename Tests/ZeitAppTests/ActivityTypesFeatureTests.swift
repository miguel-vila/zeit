import ComposableArchitecture
import Foundation
import Testing

@testable import ZeitApp

/// The editor holds one flat list and sections it by group, so every group gets
/// add, edit and remove without the reducer naming a group.
@MainActor
@Suite
struct ActivityTypesFeatureTests {
    private func type(
        _ id: String, _ group: ActivityGroup, name: String? = nil
    ) -> ActivityType {
        ActivityType(
            id: id,
            name: name ?? id.replacingOccurrences(of: "_", with: " ").capitalized,
            description: "description for \(id)",
            group: group
        )
    }

    /// One type in every group, so a change to one group can be shown not to
    /// touch the others.
    private var oneTypePerGroup: [ActivityType] {
        ActivityGroup.allCases.map { type("existing_\($0.rawValue)", $0) }
    }

    private func store(
        _ types: [ActivityType],
        primaryGroup: ActivityGroup = .work,
        mode: ActivityTypesFeature.Mode = .settings
    ) -> TestStore<ActivityTypesFeature.State, ActivityTypesFeature.Action> {
        TestStore(
            initialState: ActivityTypesFeature.State(
                mode: mode, types: types, primaryGroup: primaryGroup, isLoading: false
            )
        ) {
            ActivityTypesFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            // Unselecting asks about today's entries; the default is a day with
            // none, so the tests that are not about the confirmation see the
            // straight removal.
            $0.databaseClient.getDayRecord = { _ in nil }
        }
    }

    @Test
    func typesLoaded_sectionsEveryGroupByItsOwnTypes() async {
        let loaded = [
            type("work_coding", .work),
            type("project_coding", .personalProjects),
            type("social_media", .personal),
            type("slack", .work),
        ]

        let store = self.store([])

        await store.send(.typesLoaded(loaded, primaryGroup: .work)) {
            $0.isLoading = false
            $0.types = loaded
            $0.primaryGroup = .work
            $0.openedOnAChosenSelection = true
        }

        #expect(store.state.types(in: .work).map(\.id) == ["work_coding", "slack"])
        #expect(store.state.types(in: .personalProjects).map(\.id) == ["project_coding"])
        #expect(store.state.types(in: .personal).map(\.id) == ["social_media"])
    }

    /// Driven by `allCases`: a fourth group would be covered without edits here.
    @Test(arguments: ActivityGroup.allCases)
    func addType_appendsToTheNamedGroupOnly(group: ActivityGroup) async {
        let store = self.store(oneTypePerGroup)

        await store.send(.addType(group: group)) {
            $0.types.append(
                ActivityType(
                    id: "new_\(group.rawValue)_00000000",
                    name: "",
                    description: "",
                    group: group
                )
            )
        }

        #expect(store.state.types(in: group).count == 2)
        let untouched = ActivityGroup.allCases.filter { $0 != group }
        #expect(untouched.allSatisfy { store.state.types(in: $0).count == 1 })
    }

    @Test(arguments: ActivityGroup.allCases)
    func updateType_editsTheTypeInItsGroup(group: ActivityGroup) async {
        let store = self.store(oneTypePerGroup)
        let target = "existing_\(group.rawValue)"

        await store.send(
            .updateType(id: target, name: "Renamed", description: "New description")
        ) {
            let index = $0.types.firstIndex { $0.id == target }!
            $0.types[index].name = "Renamed"
            $0.types[index].description = "New description"
        }

        #expect(store.state.types(in: group).map(\.name) == ["Renamed"])
    }

    @Test(arguments: ActivityGroup.allCases)
    func deleteType_removesFromItsGroupAndLeavesTheRest(group: ActivityGroup) async {
        let store = self.store(oneTypePerGroup)
        let target = "existing_\(group.rawValue)"

        await store.send(.deleteType(id: target))
        await store.receive(\.todaysEntryCountLoaded)
        await store.receive(\.removeType) {
            $0.types.removeAll { $0.id == target }
        }

        #expect(store.state.types(in: group).isEmpty)
        #expect(store.state.types.count == ActivityGroup.allCases.count - 1)
    }

    @Test
    func resetToSuggestedSet_restoresTheSuggestionsForThePrimaryGroup() async {
        let store = self.store([], primaryGroup: .personalProjects)

        await store.send(.resetToSuggestedSet) {
            $0.types = ActivityCatalog.suggestedSelection(for: .personalProjects)
        }

        #expect(ActivityGroup.allCases.allSatisfy { !store.state.types(in: $0).isEmpty })
    }

    @Test
    func done_regeneratesIDsAndSavesEveryGroup() async {
        let saved = LockIsolated<[ActivityType]>([])
        let store = TestStore(
            initialState: ActivityTypesFeature.State(
                types: [
                    type("placeholder_1", .work, name: "Work Coding"),
                    type("placeholder_2", .personalProjects, name: "Project Coding"),
                    type("placeholder_3", .personal, name: "Social Media"),
                ],
                isLoading: false
            )
        ) {
            ActivityTypesFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.classificationClient.savePrimaryGroup = { _ in }
            $0.databaseClient.saveActivityTypes = { types in
                saved.setValue(types)
            }
        }

        await store.send(.done) {
            $0.types[0].id = "work_coding"
            $0.types[1].id = "project_coding"
            $0.types[2].id = "social_media"
        }

        await store.receive(\.saveCompleted)

        #expect(saved.value.map(\.id) == ["work_coding", "project_coding", "social_media"])
        #expect(saved.value.map(\.group) == [.work, .personalProjects, .personal])
    }

    // MARK: - Primary group

    /// Whatever the editor loads is what the config holds, so the number the
    /// menubar shows and the group being edited cannot drift apart.
    @Test(arguments: ActivityGroup.allCases)
    func task_loadsThePrimaryGroupFromTheConfig(primaryGroup: ActivityGroup) async {
        let loaded = oneTypePerGroup
        let store = TestStore(initialState: ActivityTypesFeature.State()) {
            ActivityTypesFeature()
        } withDependencies: {
            $0.databaseClient.getActivityTypes = { loaded }
            $0.classificationClient.primaryGroup = { primaryGroup }
        }

        await store.send(.task)

        await store.receive(\.typesLoaded) {
            $0.isLoading = false
            $0.types = loaded
            $0.primaryGroup = primaryGroup
            $0.openedOnAChosenSelection = true
        }
    }

    /// Settings offers all three groups, so each one has to be reachable from
    /// another.
    @Test(arguments: ActivityGroup.allCases)
    func setPrimaryGroup_picksAnyOfTheThreeGroups(group: ActivityGroup) async {
        let other = ActivityGroup.allCases.first { $0 != group }!
        let store = self.store(oneTypePerGroup, primaryGroup: other)

        await store.send(.setPrimaryGroup(group)) {
            $0.primaryGroup = group
        }
    }

    /// The config write and the type write happen together: a saved selection
    /// that the saved primary group has nothing in would fail validation on the
    /// next load.
    @Test(arguments: ActivityGroup.allCases)
    func done_savesThePrimaryGroupAlongsideTheTypes(group: ActivityGroup) async {
        let savedGroup = LockIsolated<ActivityGroup?>(nil)
        let store = TestStore(
            initialState: ActivityTypesFeature.State(
                types: [type("existing_\(group.rawValue)", group, name: "Only One")],
                primaryGroup: group,
                isLoading: false
            )
        ) {
            ActivityTypesFeature()
        } withDependencies: {
            $0.classificationClient.savePrimaryGroup = { savedGroup.setValue($0) }
            $0.databaseClient.saveActivityTypes = { _ in }
        }

        await store.send(.done) {
            $0.types[0].id = "only_one"
        }
        await store.receive(\.saveCompleted)

        #expect(savedGroup.value == group)
    }

    /// Nothing is written when the primary group has no types: the menubar
    /// number would be stuck at zero.
    @Test
    func done_rejectsASelectionWithNothingInThePrimaryGroup() async {
        let store = TestStore(
            initialState: ActivityTypesFeature.State(
                types: [type("social_media", .personal, name: "Social Media")],
                primaryGroup: .work,
                isLoading: false
            )
        ) {
            ActivityTypesFeature()
        } withDependencies: {
            $0.uuid = .incrementing
        }

        await store.send(.done) {
            $0.saveError = ActivityTypeValidationError
                .noTypesInPrimaryGroup(.work)
                .localizedDescription
        }
    }

    /// A single group is a valid selection as long as it is the primary one:
    /// other groups are not individually required.
    @Test(arguments: ActivityGroup.allCases)
    func isValid_withTypesInThePrimaryGroupOnly(group: ActivityGroup) {
        #expect(store([type("only_one", group)], primaryGroup: group).state.isValid)
    }

    @Test(arguments: ActivityGroup.allCases)
    func isValid_isFalseWhenThePrimaryGroupIsEmpty(primaryGroup: ActivityGroup) {
        let other = ActivityGroup.allCases.first { $0 != primaryGroup }!

        #expect(!store([type("only_one", other)], primaryGroup: primaryGroup).state.isValid)
    }

    @Test
    func isValid_isFalseWithNoTypesAtAll() {
        #expect(!store([]).state.isValid)
    }

    // MARK: - Pre-selection

    /// Onboarding opens on the suggestions for the answer, not on the starter set
    /// the database seeded itself with when nobody had answered yet.
    @Test(arguments: ActivityGroup.goals)
    func task_inOnboarding_preselectsFromTheCatalog(primaryGroup: ActivityGroup) async {
        let store = TestStore(
            initialState: ActivityTypesFeature.State(mode: .onboarding)
        ) {
            ActivityTypesFeature()
        } withDependencies: {
            $0.databaseClient.getActivityTypes = { ActivityCatalog.starterSet }
            $0.classificationClient.primaryGroup = { primaryGroup }
        }

        await store.send(.task)
        await store.receive(\.typesLoaded) {
            $0.isLoading = false
            $0.primaryGroup = primaryGroup
            $0.types = ActivityCatalog.suggestedSelection(for: primaryGroup)
        }
    }

    /// Settings shows what the machine has. Replacing it with suggestions there
    /// would throw away the selection the user came to edit.
    @Test
    func task_inSettings_loadsWhatTheDatabaseHolds() async {
        let stored = [type("my_own_thing", .work)]
        let store = TestStore(initialState: ActivityTypesFeature.State(mode: .settings)) {
            ActivityTypesFeature()
        } withDependencies: {
            $0.databaseClient.getActivityTypes = { stored }
            $0.classificationClient.primaryGroup = { .work }
        }

        await store.send(.task)
        await store.receive(\.typesLoaded) {
            $0.isLoading = false
            $0.primaryGroup = .work
            $0.openedOnAChosenSelection = true
            $0.types = stored
        }
    }

    /// In onboarding the answer is a seed for the selection, so changing it
    /// re-seeds: there is nothing of the user's to lose yet.
    @Test
    func setPrimaryGroup_inOnboarding_reseedsTheSelection() async {
        let store = self.store(
            ActivityCatalog.suggestedSelection(for: .work),
            primaryGroup: .work,
            mode: .onboarding
        )

        await store.send(.setPrimaryGroup(.personalProjects)) {
            $0.primaryGroup = .personalProjects
            $0.types = ActivityCatalog.suggestedSelection(for: .personalProjects)
        }

        #expect(store.state.types.contains { $0.id == "project_coding" })
    }

    /// In settings it does not: the selection is the user's.
    @Test
    func setPrimaryGroup_inSettings_leavesTheSelectionAlone() async {
        let selection = [type("work_coding", .work), type("project_coding", .personalProjects)]
        let store = self.store(selection, primaryGroup: .work)

        await store.send(.setPrimaryGroup(.personalProjects)) {
            $0.primaryGroup = .personalProjects
        }

        #expect(store.state.types == selection)
    }

    // MARK: - Suggestion chips

    /// A chip is a suggestion the selection does not have, so the two halves of
    /// the picker always add up to the catalog.
    @Test(arguments: ActivityGroup.allCases)
    func unselectedSuggestions_areTheCatalogMinusTheSelection(group: ActivityGroup) {
        let catalog = ActivityCatalog.suggestions(in: group)
        let selected = Array(catalog.prefix(2)).map(\.activityType)
        let state = store(selected).state

        let chips = state.unselectedSuggestions(in: group).map(\.id)
        #expect(chips == Array(catalog.dropFirst(2)).map(\.id))
        #expect(!chips.contains { id in selected.contains { $0.id == id } })
    }

    /// One click takes the suggestion whole — its description comes with it,
    /// because a description is what makes the type classifiable at all.
    @Test
    func addSuggestion_addsTheTypeWithItsDescriptionAndDropsTheChip() async {
        let suggestion = ActivityCatalog.suggestion(id: "code_review")!
        let store = self.store([type("work_coding", .work)])

        await store.send(.addSuggestion(id: suggestion.id)) {
            $0.types.append(suggestion.activityType)
        }

        #expect(store.state.types.last?.description == suggestion.description)
        #expect(store.state.types.last?.group == .work)
        #expect(!store.state.unselectedSuggestions(in: .work).contains { $0.id == "code_review" })
    }

    @Test
    func addSuggestion_isIgnoredWhenTheTypeIsAlreadySelected() async {
        let suggestion = ActivityCatalog.suggestion(id: "code_review")!
        let store = self.store([suggestion.activityType])

        await store.send(.addSuggestion(id: suggestion.id))
    }

    /// Unselecting is reversible for free: the id comes from the name, so the
    /// re-added type reconnects to the entries the removed one left behind.
    @Test
    func readdingARemovedSuggestion_regeneratesTheSameID() async {
        let suggestion = ActivityCatalog.suggestion(id: "social_media")!
        let store = self.store([type("work_coding", .work), suggestion.activityType])

        await store.send(.deleteType(id: suggestion.id))
        await store.receive(\.todaysEntryCountLoaded)
        await store.receive(\.removeType) {
            $0.types.removeAll { $0.id == suggestion.id }
        }

        await store.send(.addSuggestion(id: suggestion.id)) {
            $0.types.append(suggestion.activityType)
        }

        #expect(store.state.types.last?.id == "social_media")
    }

    // MARK: - Unselect confirmation

    private func day(_ ids: [String]) -> DayRecord {
        DayRecord(
            date: "2026-01-01",
            activities: ids.enumerated().map { index, id in
                ActivityEntry(
                    timestamp: String(format: "2026-01-01T10:%02d:00Z", index),
                    activity: Activity(rawValue: id),
                    reasoning: nil,
                    description: nil
                )
            }
        )
    }

    private func storeWithDay(
        _ types: [ActivityType], today: DayRecord
    ) -> TestStore<ActivityTypesFeature.State, ActivityTypesFeature.Action> {
        TestStore(
            initialState: ActivityTypesFeature.State(types: types, isLoading: false)
        ) {
            ActivityTypesFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.databaseClient.getDayRecord = { _ in today }
        }
    }

    /// The cost of unselecting is proportional to the entries that reference the
    /// type and invisible until the day is rendered, so the count is named.
    @Test
    func deleteType_withEntriesToday_asksFirstAndNamesTheCount() async {
        let target = type("social_media", .personal, name: "Social Media")
        let store = storeWithDay(
            [type("work_coding", .work), target],
            today: day(["social_media", "work_coding", "social_media", "idle"])
        )

        await store.send(.deleteType(id: "social_media"))
        await store.receive(\.todaysEntryCountLoaded) {
            $0.alert = .unselectWithEntries(target, count: 2)
        }

        #expect(store.state.types.count == 2)

        let message = String(state: store.state.alert!.message!)
        #expect(message.contains("2 entries"))
        #expect(message.contains(ActivityGroup.unclassifiedLabel))
    }

    @Test
    func deleteType_confirmed_removesTheType() async {
        let target = type("social_media", .personal, name: "Social Media")
        let store = storeWithDay([target], today: day(["social_media"]))

        await store.send(.deleteType(id: "social_media"))
        await store.receive(\.todaysEntryCountLoaded) {
            $0.alert = .unselectWithEntries(target, count: 1)
        }

        await store.send(.alert(.presented(.confirmRemove(id: "social_media")))) {
            $0.alert = nil
        }
        await store.receive(\.removeType) {
            $0.types = []
        }
    }

    @Test
    func deleteType_dismissed_keepsTheType() async {
        let target = type("social_media", .personal, name: "Social Media")
        let store = storeWithDay([target], today: day(["social_media"]))

        await store.send(.deleteType(id: "social_media"))
        await store.receive(\.todaysEntryCountLoaded) {
            $0.alert = .unselectWithEntries(target, count: 1)
        }

        await store.send(.alert(.dismiss)) {
            $0.alert = nil
        }

        #expect(store.state.types == [target])
    }

    /// A type with no entries today is removed on the spot: an extra click to
    /// confirm nothing would make editing the selection tedious.
    @Test
    func deleteType_withNoEntriesForThatType_skipsTheConfirmation() async {
        let store = storeWithDay(
            [type("social_media", .personal), type("work_coding", .work)],
            today: day(["work_coding", "idle"])
        )

        await store.send(.deleteType(id: "social_media"))
        await store.receive(\.todaysEntryCountLoaded)
        await store.receive(\.removeType) {
            $0.types.removeAll { $0.id == "social_media" }
        }

        #expect(store.state.alert == nil)
    }

    // MARK: - Edit / Save mode

    private struct DiskFull: LocalizedError {
        var errorDescription: String? { "The disk is full" }
    }

    /// A store over one valid type, so `done` reaches the write.
    private func savingStore(
        mode: ActivityTypesFeature.Mode = .settings,
        isEditing: Bool = false,
        saveTypes: @escaping @Sendable ([ActivityType]) async throws -> Void = { _ in }
    ) -> TestStore<ActivityTypesFeature.State, ActivityTypesFeature.Action> {
        TestStore(
            initialState: ActivityTypesFeature.State(
                mode: mode,
                types: [type("only_one", .work, name: "Only One")],
                primaryGroup: .work,
                isLoading: false,
                isEditing: isEditing
            )
        ) {
            ActivityTypesFeature()
        } withDependencies: {
            $0.classificationClient.savePrimaryGroup = { _ in }
            $0.databaseClient.saveActivityTypes = saveTypes
        }
    }

    /// Settings opens on the selection the machine has, read-only: the user has
    /// to ask for the rows before they can change them.
    @Test
    func inSettings_theEditorOpensReadOnly() {
        #expect(!store(oneTypePerGroup).state.acceptsEdits)
    }

    /// Onboarding is the step the user is there to fill in, and it has nothing
    /// saved to protect.
    @Test
    func inOnboarding_theEditorOpensEditable() {
        #expect(store(oneTypePerGroup, mode: .onboarding).state.acceptsEdits)
    }

    @Test
    func edit_makesTheRowsEditable() async {
        let store = self.store(oneTypePerGroup)

        await store.send(.edit) {
            $0.isEditing = true
        }

        #expect(store.state.acceptsEdits)
    }

    /// The return to read-only is the sign the user gets that the write
    /// happened.
    @Test
    func aSuccessfulSaveInSettings_returnsToReadOnly() async {
        let store = savingStore(isEditing: true)

        await store.send(.done)
        await store.receive(\.saveCompleted) {
            $0.isEditing = false
        }

        #expect(!store.state.acceptsEdits)
    }

    /// A failed write leaves the rows editable, with the changes and the
    /// reason: going read-only would claim a save that did not happen.
    @Test
    func aFailedSave_staysEditableAndShowsTheError() async {
        let store = savingStore(isEditing: true, saveTypes: { _ in throw DiskFull() })

        await store.send(.done)
        await store.receive(\.saveCompleted) {
            $0.saveError = "The disk is full"
        }

        #expect(store.state.acceptsEdits)
    }

    /// A selection that validation rejects is never written, so the rows stay
    /// editable for the user to fix it.
    @Test
    func aRejectedSave_staysEditable() async {
        let store = TestStore(
            initialState: ActivityTypesFeature.State(
                types: [type("social_media", .personal, name: "Social Media")],
                primaryGroup: .work,
                isLoading: false,
                isEditing: true
            )
        ) {
            ActivityTypesFeature()
        }

        await store.send(.done) {
            $0.saveError = ActivityTypeValidationError
                .noTypesInPrimaryGroup(.work)
                .localizedDescription
        }

        #expect(store.state.acceptsEdits)
    }

    /// Re-showing the pane re-reads the database, so it comes back read-only
    /// rather than offering rows over data the user did not open for editing.
    @Test
    func task_reopensTheSettingsPaneReadOnly() async {
        let stored = [type("my_own_thing", .work)]
        let store = TestStore(
            initialState: ActivityTypesFeature.State(mode: .settings, isEditing: true)
        ) {
            ActivityTypesFeature()
        } withDependencies: {
            $0.databaseClient.getActivityTypes = { stored }
            $0.classificationClient.primaryGroup = { .work }
        }

        await store.send(.task) {
            $0.isEditing = false
        }
        await store.receive(\.typesLoaded) {
            $0.isLoading = false
            $0.primaryGroup = .work
            $0.openedOnAChosenSelection = true
            $0.types = stored
        }

        #expect(!store.state.acceptsEdits)
    }

    /// Onboarding's Continue saves and moves the wizard on; there is no
    /// read-only state for the step to come back to.
    @Test
    func aSuccessfulSaveInOnboarding_leavesTheStepEditable() async {
        let store = savingStore(mode: .onboarding)

        await store.send(.done)
        await store.receive(\.saveCompleted)

        #expect(store.state.acceptsEdits)
    }
}
