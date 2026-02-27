import ComposableArchitecture
import Foundation

/// Other settings feature with work hours configuration.
@Reducer
struct OtherSettingsFeature {
    @ObservableState
    struct State: Equatable {
        var startHour: Int = ZeitConfig.defaultWorkHours.startHour
        var startMinute: Int = ZeitConfig.defaultWorkHours.startMinute
        var endHour: Int = ZeitConfig.defaultWorkHours.endHour
        var endMinute: Int = ZeitConfig.defaultWorkHours.endMinute
        var workDays: Set<ZeitConfig.Weekday> = ZeitConfig.defaultWorkDays
    }

    enum Action {
        case task
        case workHoursLoaded(ZeitConfig.WorkHoursConfig)
        case setStartHour(Int)
        case setStartMinute(Int)
        case setEndHour(Int)
        case setEndMinute(Int)
        case toggleWorkDay(ZeitConfig.Weekday)
        case done
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                return .run { send in
                    let config = ZeitConfig.load()
                    await send(.workHoursLoaded(config.workHours))
                }

            case .workHoursLoaded(let config):
                state.startHour = config.startHour
                state.startMinute = config.startMinute
                state.endHour = config.endHour
                state.endMinute = config.endMinute
                state.workDays = config.workDays
                return .none

            case .setStartHour(let hour):
                state.startHour = hour
                return .none

            case .setStartMinute(let minute):
                state.startMinute = minute
                return .none

            case .setEndHour(let hour):
                state.endHour = hour
                return .none

            case .setEndMinute(let minute):
                state.endMinute = minute
                return .none

            case .toggleWorkDay(let day):
                if state.workDays.contains(day) {
                    if state.workDays.count > 1 {
                        state.workDays.remove(day)
                    }
                } else {
                    state.workDays.insert(day)
                }
                return .none

            case .done:
                let startHour = state.startHour
                let startMinute = state.startMinute
                let endHour = state.endHour
                let endMinute = state.endMinute
                let workDays = state.workDays
                return .run { _ in
                    try? ZeitConfig.saveWorkHours(
                        startHour: startHour, startMinute: startMinute,
                        endHour: endHour, endMinute: endMinute,
                        workDays: workDays
                    )
                }
            }
        }
    }
}
