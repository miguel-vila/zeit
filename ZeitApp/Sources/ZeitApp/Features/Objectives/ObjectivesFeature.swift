import ComposableArchitecture
import Foundation

@Reducer
struct ObjectivesFeature {
    @ObservableState
    struct State: Equatable {
        var date: String
        var mainObjective: String = ""
        var secondary1: String = ""
        var secondary2: String = ""
        var isLoading: Bool = false
        var isSaving: Bool = false
        var savedSuccessfully: Bool = false
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case task
        case objectivesLoaded(DayObjectives?)
        case save
        case saved
        case saveFailed(String)
        case cancel
    }

    @Dependency(\.databaseClient) var database
    @Dependency(\.dismiss) var dismiss

    var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .binding:
                state.savedSuccessfully = false
                return .none

            case .task:
                state.isLoading = true
                let date = state.date

                return .run { send in
                    let objectives = try? await database.getDayObjectives(date)
                    await send(.objectivesLoaded(objectives))
                }

            case .objectivesLoaded(let objectives):
                state.isLoading = false

                if let objectives {
                    state.mainObjective = objectives.mainObjective
                    if objectives.secondaryObjectives.count > 0 {
                        state.secondary1 = objectives.secondaryObjectives[0]
                    }
                    if objectives.secondaryObjectives.count > 1 {
                        state.secondary2 = objectives.secondaryObjectives[1]
                    }
                }
                return .none

            case .save:
                guard !state.mainObjective.trimmingCharacters(in: .whitespaces).isEmpty else {
                    return .none
                }

                state.isSaving = true
                let date = state.date
                let main = state.mainObjective.trimmingCharacters(in: .whitespaces)

                var secondaryList: [String] = []
                let s1 = state.secondary1.trimmingCharacters(in: .whitespaces)
                let s2 = state.secondary2.trimmingCharacters(in: .whitespaces)
                if !s1.isEmpty { secondaryList.append(s1) }
                if !s2.isEmpty { secondaryList.append(s2) }
                let secondary = secondaryList  // Create immutable copy

                return .run { send in
                    do {
                        try await database.saveDayObjectives(date, main, secondary)
                        await send(.saved)
                    } catch {
                        await send(.saveFailed(error.localizedDescription))
                    }
                }

            case .saved:
                state.isSaving = false
                state.savedSuccessfully = true
                return .none

            case .saveFailed:
                state.isSaving = false
                return .none

            case .cancel:
                return .run { _ in
                    await dismiss()
                }
            }
        }
    }
}
