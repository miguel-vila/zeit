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
        var activityTypes: ActivityTypesFeature.State = .init()
        var debugModeEnabled: Bool = UserDefaults.standard.bool(forKey: "debugModeEnabled")
        var isCompleted: Bool = false

        enum Tab: String, CaseIterable, Equatable {
            case permissions = "Permissions"
            case models = "Models"
            case workHours = "Work Hours"
            case activityTypes = "Activity Types"
            case debug = "Debug"
            case about = "About"

            var icon: String {
                switch self {
                case .permissions: return "lock.shield"
                case .models: return "cpu"
                case .workHours: return "clock.fill"
                case .activityTypes: return "list.bullet.rectangle"
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
        var startMinute: Int = ZeitConfig.defaultWorkHours.startMinute
        var endHour: Int = ZeitConfig.defaultWorkHours.endHour
        var endMinute: Int = ZeitConfig.defaultWorkHours.endMinute
        var workDays: Set<ZeitConfig.Weekday> = ZeitConfig.defaultWorkDays
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
        case workHoursLoaded(ZeitConfig.WorkHoursConfig)
        case setStartHour(Int)
        case setStartMinute(Int)
        case setEndHour(Int)
        case setEndMinute(Int)
        case toggleWorkDay(ZeitConfig.Weekday)
        case saveWorkHours
        case workHoursSaved
        case workHoursSaveFailed(String)

        // Activity Types
        case activityTypes(ActivityTypesFeature.Action)

        // Debug
        case toggleDebugMode

        // Window
        case closeSettings
    }

    @Dependency(\.permissionsClient) var permissions
    @Dependency(\.modelClient) var modelClient

    var body: some ReducerOf<Self> {
        Scope(state: \.activityTypes, action: \.activityTypes) {
            ActivityTypesFeature()
        }

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
                        await send(.workHoursLoaded(config.workHours))
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

            case .workHoursLoaded(let config):
                state.workHours.startHour = config.startHour
                state.workHours.startMinute = config.startMinute
                state.workHours.endHour = config.endHour
                state.workHours.endMinute = config.endMinute
                state.workHours.workDays = config.workDays
                return .none

            case .setStartHour(let hour):
                state.workHours.startHour = hour
                state.workHours.saveError = nil
                return .none

            case .setStartMinute(let minute):
                state.workHours.startMinute = minute
                state.workHours.saveError = nil
                return .none

            case .setEndHour(let hour):
                state.workHours.endHour = hour
                state.workHours.saveError = nil
                return .none

            case .setEndMinute(let minute):
                state.workHours.endMinute = minute
                state.workHours.saveError = nil
                return .none

            case .toggleWorkDay(let day):
                if state.workHours.workDays.contains(day) {
                    // Don't allow removing the last work day
                    if state.workHours.workDays.count > 1 {
                        state.workHours.workDays.remove(day)
                    }
                } else {
                    state.workHours.workDays.insert(day)
                }
                state.workHours.saveError = nil
                return .none

            case .saveWorkHours:
                let startHour = state.workHours.startHour
                let startMinute = state.workHours.startMinute
                let endHour = state.workHours.endHour
                let endMinute = state.workHours.endMinute
                let workDays = state.workHours.workDays
                return .run { send in
                    do {
                        try ZeitConfig.saveWorkHours(
                            startHour: startHour, startMinute: startMinute,
                            endHour: endHour, endMinute: endMinute,
                            workDays: workDays
                        )
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

            case .activityTypes:
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
