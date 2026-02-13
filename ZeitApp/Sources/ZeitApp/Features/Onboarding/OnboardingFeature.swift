import ComposableArchitecture
import Foundation

/// Onboarding feature that guides through permissions and model download.
/// Step 1: Permissions (Screen Recording + Accessibility)
/// Step 2: Model Download (Vision + Text models)
@Reducer
struct OnboardingFeature {
    @ObservableState
    struct State: Equatable {
        var step: Step = .permissions
        var permissions: PermissionsFeature.State = .init()
        var modelDownload: ModelDownloadFeature.State = .init()
        var isCompleted: Bool = false

        enum Step: Equatable {
            case permissions
            case modelDownload
        }
    }

    enum Action {
        case permissions(PermissionsFeature.Action)
        case modelDownload(ModelDownloadFeature.Action)
        case completed
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.permissions, action: \.permissions) {
            PermissionsFeature()
        }

        Scope(state: \.modelDownload, action: \.modelDownload) {
            ModelDownloadFeature()
        }

        Reduce { state, action in
            switch action {
            // MARK: - Permissions step

            case .permissions(.allPermissionsGranted):
                // Don't auto-advance — let the user click "Continue"
                return .none

            case .permissions(.skip):
                // Skip permissions, move to model download
                state.step = .modelDownload
                return .none

            case .permissions(.continuePressed):
                // Permissions done, move to model download
                state.step = .modelDownload
                return .none

            case .permissions:
                return .none

            // MARK: - Model download step

            case .modelDownload(.allModelsReady):
                // Don't auto-close — let the user click "Continue"
                return .none

            case .modelDownload(.skip):
                return .send(.completed)

            case .modelDownload(.continuePressed):
                return .send(.completed)

            case .modelDownload:
                return .none

            // MARK: - Completion

            case .completed:
                state.isCompleted = true
                return .none
            }
        }
    }
}
