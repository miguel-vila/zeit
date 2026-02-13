import ComposableArchitecture
import Foundation

/// Other settings feature with debug mode toggle.
@Reducer
struct OtherSettingsFeature {
    @ObservableState
    struct State: Equatable {
        var debugModeEnabled: Bool = UserDefaults.standard.bool(forKey: "debugModeEnabled")
    }

    enum Action {
        case toggleDebugMode
        case done
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .toggleDebugMode:
                state.debugModeEnabled.toggle()
                UserDefaults.standard.set(state.debugModeEnabled, forKey: "debugModeEnabled")
                return .none

            case .done:
                return .none
            }
        }
    }
}
