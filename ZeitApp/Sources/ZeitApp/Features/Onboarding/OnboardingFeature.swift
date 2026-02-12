import ComposableArchitecture
import Foundation

/// Unified onboarding feature that keeps the window open across all steps:
/// 1. Permissions — grant Screen Recording + Accessibility
/// 2. Setup — install CLI + LaunchAgents
@Reducer
struct OnboardingFeature {
    @ObservableState
    struct State: Equatable {
        var step: Step = .permissions
        var permissions: PermissionsFeature.State = .init()
        var setup: SetupFeature.State = .init()

        enum Step: Equatable {
            case permissions
            case setup
        }
    }

    enum Action {
        case permissions(PermissionsFeature.Action)
        case setup(SetupFeature.Action)
        case completed
    }

    @Dependency(\.permissionsClient) var permissionsClient

    var body: some ReducerOf<Self> {
        Scope(state: \.permissions, action: \.permissions) {
            PermissionsFeature()
        }
        Scope(state: \.setup, action: \.setup) {
            SetupFeature()
        }

        Reduce { state, action in
            switch action {
            case .permissions(.allPermissionsGranted):
                // Move to next step instead of dismissing
                state.step = .setup
                return .none

            case .permissions(.skip):
                // Skip means skip the entire onboarding
                return .send(.completed)

            case .permissions(.continuePressed):
                // Continue also advances to setup
                state.step = .setup
                return .none

            case .permissions:
                return .none

            case .setup(.close):
                return .send(.completed)

            case .setup(.skip):
                return .send(.completed)

            case .setup(.installCompleted(.success)):
                // Stay on setup to show success message; user closes via .close
                return .none

            case .setup:
                return .none

            case .completed:
                // Parent handles dismissal
                return .none
            }
        }
    }
}
