import ComposableArchitecture
import Foundation

/// Feature for editing activity types (used in both onboarding and settings).
@Reducer
struct ActivityTypesFeature {
    @ObservableState
    struct State: Equatable {
        var workTypes: [ActivityType] = []
        var personalTypes: [ActivityType] = []
        var isLoading: Bool = true
        var saveError: String?

        /// Whether the current configuration is valid for saving/continuing
        var isValid: Bool {
            !workTypes.isEmpty && !personalTypes.isEmpty
                && workTypes.count + personalTypes.count <= ActivityTypeValidator.maxTotalTypes
                && workTypes.allSatisfy({ ActivityTypeValidator.validateField($0) == nil })
                && personalTypes.allSatisfy({ ActivityTypeValidator.validateField($0) == nil })
        }
    }

    enum Action {
        case task
        case typesLoaded([ActivityType])

        // Work types
        case addWorkType
        case updateWorkType(id: String, name: String?, description: String?)
        case deleteWorkType(id: String)

        // Personal types
        case addPersonalType
        case updatePersonalType(id: String, name: String?, description: String?)
        case deletePersonalType(id: String)

        // Bulk
        case resetToDefaults
        case clearAll

        // Save
        case done
        case saveCompleted(Result<Void, Error>)
    }

    @Dependency(\.databaseClient) var database

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                state.isLoading = true
                return .run { send in
                    let types = try await database.getActivityTypes()
                    await send(.typesLoaded(types))
                }

            case .typesLoaded(let types):
                state.isLoading = false
                state.workTypes = types.filter(\.isWork)
                state.personalTypes = types.filter { !$0.isWork }
                return .none

            // MARK: - Work types

            case .addWorkType:
                let newType = ActivityType(
                    id: "new_work_\(UUID().uuidString.prefix(8).lowercased())",
                    name: "",
                    description: "",
                    isWork: true
                )
                state.workTypes.append(newType)
                return .none

            case .updateWorkType(let id, let name, let description):
                guard let index = state.workTypes.firstIndex(where: { $0.id == id }) else {
                    return .none
                }
                if let name = name {
                    state.workTypes[index].name = name
                }
                if let description = description {
                    state.workTypes[index].description = description
                }
                state.saveError = nil
                return .none

            case .deleteWorkType(let id):
                state.workTypes.removeAll { $0.id == id }
                return .none

            // MARK: - Personal types

            case .addPersonalType:
                let newType = ActivityType(
                    id: "new_personal_\(UUID().uuidString.prefix(8).lowercased())",
                    name: "",
                    description: "",
                    isWork: false
                )
                state.personalTypes.append(newType)
                return .none

            case .updatePersonalType(let id, let name, let description):
                guard let index = state.personalTypes.firstIndex(where: { $0.id == id }) else {
                    return .none
                }
                if let name = name {
                    state.personalTypes[index].name = name
                }
                if let description = description {
                    state.personalTypes[index].description = description
                }
                state.saveError = nil
                return .none

            case .deletePersonalType(let id):
                state.personalTypes.removeAll { $0.id == id }
                return .none

            // MARK: - Bulk

            case .resetToDefaults:
                state.workTypes = ActivityType.defaultWorkTypes
                state.personalTypes = ActivityType.defaultPersonalTypes
                state.saveError = nil
                return .none

            case .clearAll:
                state.workTypes = []
                state.personalTypes = []
                state.saveError = nil
                return .none

            // MARK: - Save

            case .done:
                // Regenerate IDs from names before saving
                for index in state.workTypes.indices {
                    state.workTypes[index].id = ActivityType.generateID(
                        from: state.workTypes[index].name
                    )
                }
                for index in state.personalTypes.indices {
                    state.personalTypes[index].id = ActivityType.generateID(
                        from: state.personalTypes[index].name
                    )
                }

                let errors = ActivityTypeValidator.validateAll(
                    work: state.workTypes,
                    personal: state.personalTypes
                )
                if let firstError = errors.first {
                    state.saveError = firstError.localizedDescription
                    return .none
                }

                let allTypes = state.workTypes + state.personalTypes
                return .run { send in
                    do {
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
