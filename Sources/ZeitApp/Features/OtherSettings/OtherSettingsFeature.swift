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
        case scheduleLoaded(ZeitConfig.ScheduleConfig, ZeitConfig.TrackingConfig)
        case setAlways(Bool)
        case addWindow
        case removeWindow(UUID)
        case changeWindow(ScheduleWindowDraft)
        case setInterval(Int)
        case setSkipOnBattery(Bool)
        case setDayStartHour(Int)
        case done
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                return .run { send in
                    let config = ZeitConfig.load()
                    await send(.scheduleLoaded(config.schedule, config.tracking))
                }

            case .scheduleLoaded(let schedule, let tracking):
                state.editor.load(schedule, tracking: tracking)
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

            case .setInterval(let seconds):
                state.editor.intervalSeconds = ScheduleEditorState.clamped(seconds)
                return .none

            case .setSkipOnBattery(let skip):
                state.editor.skipOnBattery = skip
                return .none

            case .setDayStartHour(let hour):
                state.editor.dayStartHour = DayAttribution.clamped(dayStartHour: hour)
                return .none

            case .done:
                let schedule = state.editor.schedule
                let tracking = state.editor.tracking
                return .run { _ in
                    try? ZeitConfig.saveSchedule(schedule, tracking: tracking)
                }
            }
        }
    }
}
