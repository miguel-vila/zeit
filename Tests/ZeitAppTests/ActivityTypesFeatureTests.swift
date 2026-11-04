import ComposableArchitecture
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
        _ types: [ActivityType]
    ) -> TestStore<ActivityTypesFeature.State, ActivityTypesFeature.Action> {
        TestStore(
            initialState: ActivityTypesFeature.State(types: types, isLoading: false)
        ) {
            ActivityTypesFeature()
        } withDependencies: {
            $0.uuid = .incrementing
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

        await store.send(.typesLoaded(loaded)) {
            $0.isLoading = false
            $0.types = loaded
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

        await store.send(.deleteType(id: target)) {
            $0.types.removeAll { $0.id == target }
        }

        #expect(store.state.types(in: group).isEmpty)
        #expect(store.state.types.count == ActivityGroup.allCases.count - 1)
    }

    @Test
    func resetToDefaults_restoresEveryGroupOfTheStarterSet() async {
        let store = self.store([])

        await store.send(.resetToDefaults) {
            $0.types = ActivityType.defaultTypes
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

    /// A single group is a valid selection: groups are not individually required.
    @Test(arguments: ActivityGroup.allCases)
    func isValid_withTypesInOneGroupOnly(group: ActivityGroup) {
        #expect(store([type("only_one", group)]).state.isValid)
    }

    @Test
    func isValid_isFalseWithNoTypesAtAll() {
        #expect(!store([]).state.isValid)
    }
}
