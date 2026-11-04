import ComposableArchitecture
import Foundation

/// Feature for editing activity types (used in both onboarding and settings).
///
/// Types are held in one flat list and sectioned by their group when rendered, so
/// the editor gains a section the moment `ActivityGroup` gains a case.
@Reducer
struct ActivityTypesFeature {
    @ObservableState
    struct State: Equatable {
        var types: [ActivityType] = []
        /// The group this machine is judged by, saved to the config on `done`.
        var primaryGroup: ActivityGroup = ZeitConfig.defaultClassification.primaryGroup
        var isLoading: Bool = true
        var saveError: String?

        /// Whether the current configuration is valid for saving/continuing.
        ///
        /// Groups other than the primary one are not required to be populated: a
        /// machine has a group when it has types in that group.
        var isValid: Bool {
            !types.isEmpty
                && types.count <= ActivityTypeValidator.maxTotalTypes
                && types.contains { $0.group == primaryGroup }
                && types.allSatisfy({ ActivityTypeValidator.validateField($0) == nil })
        }

        /// The types belonging to `group`, in the order they were loaded or added.
        func types(in group: ActivityGroup) -> [ActivityType] {
            types.filter { $0.group == group }
        }
    }

    enum Action {
        case task
        case typesLoaded([ActivityType], primaryGroup: ActivityGroup)

        // Editing
        case setPrimaryGroup(ActivityGroup)
        case addType(group: ActivityGroup)
        case updateType(id: String, name: String?, description: String?)
        case deleteType(id: String)

        // Bulk
        case resetToDefaults
        case clearAll

        // Save
        case done
        case saveCompleted(Result<Void, Error>)
    }

    @Dependency(\.databaseClient) var database
    @Dependency(\.classificationClient) var classification
    @Dependency(\.uuid) var uuid

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                state.isLoading = true
                return .run { send in
                    let types = try await database.getActivityTypes()
                    await send(.typesLoaded(types, primaryGroup: classification.primaryGroup()))
                }

            case .typesLoaded(let types, let primaryGroup):
                state.isLoading = false
                state.types = types
                state.primaryGroup = primaryGroup
                return .none

            // MARK: - Editing

            case .setPrimaryGroup(let group):
                state.primaryGroup = group
                state.saveError = nil
                return .none

            case .addType(let group):
                state.types.append(
                    ActivityType(
                        id: "new_\(group.rawValue)_\(uuid().uuidString.prefix(8).lowercased())",
                        name: "",
                        description: "",
                        group: group
                    )
                )
                return .none

            case .updateType(let id, let name, let description):
                guard let index = state.types.firstIndex(where: { $0.id == id }) else {
                    return .none
                }
                if let name = name {
                    state.types[index].name = name
                }
                if let description = description {
                    state.types[index].description = description
                }
                state.saveError = nil
                return .none

            case .deleteType(let id):
                state.types.removeAll { $0.id == id }
                return .none

            // MARK: - Bulk

            case .resetToDefaults:
                state.types = ActivityType.defaultTypes
                state.saveError = nil
                return .none

            case .clearAll:
                state.types = []
                state.saveError = nil
                return .none

            // MARK: - Save

            case .done:
                // Regenerate IDs from names before saving
                for index in state.types.indices {
                    state.types[index].id = ActivityType.generateID(
                        from: state.types[index].name
                    )
                }

                let allTypes = state.types
                let primaryGroup = state.primaryGroup

                let errors = ActivityTypeValidator.validateAll(
                    allTypes, primaryGroup: primaryGroup
                )
                if let firstError = errors.first {
                    state.saveError = firstError.localizedDescription
                    return .none
                }

                return .run { send in
                    do {
                        try classification.savePrimaryGroup(primaryGroup)
                        try await database.saveActivityTypes(allTypes)
                        await send(.saveCompleted(.success(())))
                    } catch {
                        await send(.saveCompleted(.failure(error)))
                    }
                }

            case .saveCompleted(.success):
                state.saveError = nil
                return .none

            case .saveCompleted(.failure(let error)):
                state.saveError = error.localizedDescription
                return .none
            }
        }
    }
}
