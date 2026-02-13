import ComposableArchitecture
import Foundation

/// Settings window feature with tabbed navigation.
/// Tabs: Permissions, Models, Debug, About.
@Reducer
struct SettingsFeature {
    @ObservableState
    struct State: Equatable {
        var selectedTab: Tab = .permissions
        var permissions: SettingsPermissionsState = .init()
        var models: SettingsModelsState = .init()
        var debugModeEnabled: Bool = UserDefaults.standard.bool(forKey: "debugModeEnabled")
        var isCompleted: Bool = false

        enum Tab: String, CaseIterable, Equatable {
            case permissions = "Permissions"
            case models = "Models"
            case debug = "Debug"
            case about = "About"

            var icon: String {
                switch self {
                case .permissions: return "lock.shield"
                case .models: return "cpu"
                case .debug: return "ladybug.fill"
                case .about: return "info.circle"
                }
            }
        }
    }

    // MARK: - Permissions tab state

    struct SettingsPermissionsState: Equatable {
        var screenRecordingGranted: Bool = false
        var accessibilityGranted: Bool = false
    }

    // MARK: - Models tab state

    struct SettingsModelsState: Equatable {
        var models: [ModelInfo] = []

        struct ModelInfo: Equatable, Identifiable {
            let configName: String
            let displayName: String
            let approximateSizeGB: Double
            let isVision: Bool
            var isDownloaded: Bool

            var id: String { configName }
        }
    }

    enum Action {
        case task
        case selectTab(State.Tab)

        // Permissions
        case permissionsUpdated(screenRecording: Bool, accessibility: Bool)

        // Models
        case modelStatusesLoaded([ModelProgress])

        // Debug
        case toggleDebugMode

        // Window
        case closeSettings
    }

    @Dependency(\.permissionsClient) var permissions
    @Dependency(\.modelClient) var modelClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                return .merge(
                    .run { send in
                        let screen = permissions.screenRecordingStatus() == .granted
                        let accessibility = permissions.accessibilityStatus() == .granted
                        await send(.permissionsUpdated(
                            screenRecording: screen,
                            accessibility: accessibility
                        ))
                    },
                    .run { send in
                        let statuses = await modelClient.getModelStatuses()
                        await send(.modelStatusesLoaded(statuses))
                    }
                )

            case .selectTab(let tab):
                state.selectedTab = tab
                return .none

            case .permissionsUpdated(let screen, let accessibility):
                state.permissions.screenRecordingGranted = screen
                state.permissions.accessibilityGranted = accessibility
                return .none

            case .modelStatusesLoaded(let statuses):
                state.models.models = MLXModelManager.supportedModels.map { model in
                    let status = statuses.first { $0.modelName == model.configName }
                    return SettingsModelsState.ModelInfo(
                        configName: model.configName,
                        displayName: model.displayName,
                        approximateSizeGB: model.approximateSizeGB,
                        isVision: model.isVision,
                        isDownloaded: status?.status == .downloaded
                    )
                }
                return .none

            case .toggleDebugMode:
                state.debugModeEnabled.toggle()
                UserDefaults.standard.set(state.debugModeEnabled, forKey: "debugModeEnabled")
                return .none

            case .closeSettings:
                state.isCompleted = true
                return .none
            }
        }
    }
}
