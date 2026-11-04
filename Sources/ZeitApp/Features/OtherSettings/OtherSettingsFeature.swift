import ComposableArchitecture
import Foundation

/// Onboarding's last step: the tracking schedule.
@Reducer
struct OtherSettingsFeature {
    @ObservableState
    struct State: Equatable {
        var editor: ScheduleEditorState = .init()
    }

    enum Action {
        case task
        case scheduleLoaded(ZeitConfig.ScheduleConfig)
        case setAlways(Bool)
        case addWindow
        case removeWindow(UUID)
        case changeWindow(ScheduleWindowDraft)
        case done
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                return .run { send in
                    let config = ZeitConfig.load()
                    await send(.scheduleLoaded(config.schedule))
                }

            case .scheduleLoaded(let schedule):
                state.editor.load(schedule)
                return .none

            case .setAlways(let isAlways):
                state.editor.isAlways = isAlways
                return .none

            case .addWindow:
                state.editor.addWindow()
                return .none

            case .removeWindow(let id):
                state.editor.removeWindow(id: id)
                return .none

            case .changeWindow(let window):
                state.editor.update(window)
                return .none

            case .done:
                let schedule = state.editor.schedule
                return .run { _ in
                    try? ZeitConfig.saveSchedule(schedule)
                }
            }
        }
    }
}
