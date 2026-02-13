import ComposableArchitecture
import Foundation

/// Onboarding feature that shows the permissions window on first launch.
@Reducer
struct OnboardingFeature {
    @ObservableState
    struct State: Equatable {
        var permissions: PermissionsFeature.State = .init()
        var isCompleted: Bool = false
    }

    enum Action {
        case permissions(PermissionsFeature.Action)
        case completed
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.permissions, action: \.permissions) {
            PermissionsFeature()
        }

        Reduce { state, action in
            switch action {
            case .permissions(.allPermissionsGranted):
                // Don't auto-close — let the user see that all permissions are granted
                // and click "Continue" explicitly. This keeps the window open until
                // the user has addressed all permissions.
                return .none

            case .permissions(.skip):
                return .send(.completed)

            case .permissions(.continuePressed):
                return .send(.completed)

            case .permissions:
                return .none

            case .completed:
                state.isCompleted = true
                return .none
            }
        }
    }
}
