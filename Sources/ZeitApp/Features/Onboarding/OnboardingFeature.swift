import ComposableArchitecture
import Foundation

/// Onboarding feature that guides through permissions, model download, activity types, and settings.
/// Step 1: Permissions (Screen Recording + Accessibility)
/// Step 2: Model Download (Vision + Text models)
/// Step 3: Activity Types (Customize tracked activity categories)
/// Step 4: Other Settings (Debug mode toggle, etc.)
@Reducer
struct OnboardingFeature {
    @ObservableState
    struct State: Equatable {
        var step: Step = .permissions
        var permissions: PermissionsFeature.State = .init()
        var modelDownload: ModelDownloadFeature.State = .init()
        var activityTypes: ActivityTypesFeature.State = .init()
        var otherSettings: OtherSettingsFeature.State = .init()
        var isCompleted: Bool = false

        enum Step: Equatable {
            case permissions
            case modelDownload
            case activityTypes
            case otherSettings
        }
    }

    enum Action {
        case permissions(PermissionsFeature.Action)
        case modelDownload(ModelDownloadFeature.Action)
        case activityTypes(ActivityTypesFeature.Action)
        case otherSettings(OtherSettingsFeature.Action)
        case completed
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.permissions, action: \.permissions) {
            PermissionsFeature()
        }

        Scope(state: \.modelDownload, action: \.modelDownload) {
            ModelDownloadFeature()
        }

        Scope(state: \.activityTypes, action: \.activityTypes) {
            ActivityTypesFeature()
        }

        Scope(state: \.otherSettings, action: \.otherSettings) {
            OtherSettingsFeature()
        }

        Reduce { state, action in
            switch action {
            // MARK: - Permissions step

            case .permissions(.allPermissionsGranted):
                // Don't auto-advance — let the user click "Continue"
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

            case .modelDownload(.continuePressed):
                state.step = .activityTypes
                return .none

            case .modelDownload:
                return .none

            // MARK: - Activity types step

            case .activityTypes(.saveCompleted(.success)):
                state.step = .otherSettings
                return .none

            case .activityTypes:
                return .none

            // MARK: - Other settings step

            case .otherSettings(.done):
                return .send(.completed)

            case .otherSettings:
                return .none

            // MARK: - Completion

            case .completed:
                state.isCompleted = true
                return .none
            }
        }
    }
}
