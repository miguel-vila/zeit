import ComposableArchitecture
import Foundation

/// Settings window feature with tabbed navigation.
/// Tabs: Permissions, Models, Work Hours, Debug, About.
@Reducer
struct SettingsFeature {
    @ObservableState
    struct State: Equatable {
        var selectedTab: Tab = .permissions
        var permissions: SettingsPermissionsState = .init()
        var models: SettingsModelsState = .init()
        var workHours: WorkHoursState = .init()
        var debugModeEnabled: Bool = UserDefaults.standard.bool(forKey: "debugModeEnabled")
        var isCompleted: Bool = false

        enum Tab: String, CaseIterable, Equatable {
            case permissions = "Permissions"
            case models = "Models"
            case workHours = "Work Hours"
            case debug = "Debug"
            case about = "About"

            var icon: String {
                switch self {
                case .permissions: return "lock.shield"
                case .models: return "cpu"
                case .workHours: return "clock.fill"
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

    // MARK: - Work Hours tab state

    struct WorkHoursState: Equatable {
        var startHour: Int = ZeitConfig.defaultWorkHours.startHour
        var endHour: Int = ZeitConfig.defaultWorkHours.endHour
        var saveError: String?
    }

    enum Action {
        case task
        case selectTab(State.Tab)

        // Permissions
        case permissionsUpdated(screenRecording: Bool, accessibility: Bool)

        // Models
        case modelStatusesLoaded([ModelProgress])

        // Work Hours
        case workHoursLoaded(startHour: Int, endHour: Int)
        case setStartHour(Int)
        case setEndHour(Int)
        case saveWorkHours
        case workHoursSaved
        case workHoursSaveFailed(String)

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
                    },
                    .run { send in
                        let config = ZeitConfig.load()
                        await send(.workHoursLoaded(
                            startHour: config.workHours.startHour,
                            endHour: config.workHours.endHour
                        ))
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

            case .workHoursLoaded(let startHour, let endHour):
                state.workHours.startHour = startHour
                state.workHours.endHour = endHour
                return .none

            case .setStartHour(let hour):
                state.workHours.startHour = hour
                state.workHours.saveError = nil
                return .none

            case .setEndHour(let hour):
                state.workHours.endHour = hour
                state.workHours.saveError = nil
                return .none

            case .saveWorkHours:
                let startHour = state.workHours.startHour
                let endHour = state.workHours.endHour
                return .run { send in
                    do {
                        try ZeitConfig.saveWorkHours(startHour: startHour, endHour: endHour)
                        await send(.workHoursSaved)
                    } catch {
                        await send(.workHoursSaveFailed(error.localizedDescription))
                    }
                }

            case .workHoursSaved:
                state.workHours.saveError = nil
                return .none

            case .workHoursSaveFailed(let error):
                state.workHours.saveError = error
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
