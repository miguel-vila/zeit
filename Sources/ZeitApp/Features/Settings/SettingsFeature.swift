import ComposableArchitecture
import Foundation

/// Settings window feature with tabbed navigation.
/// Tabs: Permissions, Models, Schedule, Activity Types, About.
@Reducer
struct SettingsFeature {
    @ObservableState
    struct State: Equatable {
        var selectedTab: Tab = .permissions
        var permissions: SettingsPermissionsState = .init()
        var models: ModelDownloadFeature.State = .init()
        var schedule: ScheduleState = .init()
        var activityTypes: ActivityTypesFeature.State = .init()
        var isCompleted: Bool = false

        enum Tab: String, CaseIterable, Equatable {
            case permissions = "Permissions"
            case models = "Models"
            case schedule = "Schedule"
            case activityTypes = "Activity Types"
            case about = "About"

            var icon: String {
                switch self {
                case .permissions: return "lock.shield"
                case .models: return "cpu"
                case .schedule: return "clock.fill"
                case .activityTypes: return "list.bullet.rectangle"
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

    // MARK: - Schedule tab state

    struct ScheduleState: Equatable {
        var editor: ScheduleEditorState = .init()
        var saveError: String?
    }

    enum Action {
        case task
        case selectTab(State.Tab)

        // Permissions
        case permissionsUpdated(screenRecording: Bool, accessibility: Bool)

        // Models — delegated to the shared model-download reducer
        case models(ModelDownloadFeature.Action)

        // Schedule
        case scheduleLoaded(ZeitConfig.ScheduleConfig, ZeitConfig.TrackingConfig)
        case setAlways(Bool)
        case addWindow
        case removeWindow(UUID)
        case changeWindow(ScheduleWindowDraft)
        case setInterval(Int)
        case setSkipOnBattery(Bool)
        case saveSchedule
        case scheduleSaved
        case scheduleSaveFailed(String)

        // Activity Types
        case activityTypes(ActivityTypesFeature.Action)

        // Window
        case closeSettings
    }

    @Dependency(\.permissionsClient) var permissions
    @Dependency(\.modelClient) var modelClient

    var body: some ReducerOf<Self> {
        Scope(state: \.activityTypes, action: \.activityTypes) {
            ActivityTypesFeature()
        }

        Scope(state: \.models, action: \.models) {
            ModelDownloadFeature()
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
                    .send(.models(.task)),
                    .run { send in
                        let config = ZeitConfig.load()
                        await send(.scheduleLoaded(config.schedule, config.tracking))
                    }
                )

            case .selectTab(let tab):
                state.selectedTab = tab
                return .none

            case .permissionsUpdated(let screen, let accessibility):
                state.permissions.screenRecordingGranted = screen
                state.permissions.accessibilityGranted = accessibility
                return .none

            case .models:
                return .none

            case .scheduleLoaded(let schedule, let tracking):
                state.schedule.editor.load(schedule, tracking: tracking)
                return .none

            case .setAlways(let isAlways):
                state.schedule.editor.isAlways = isAlways
                state.schedule.saveError = nil
                return .none

            case .addWindow:
                state.schedule.editor.addWindow()
                state.schedule.saveError = nil
                return .none

            case .removeWindow(let id):
                state.schedule.editor.removeWindow(id: id)
                state.schedule.saveError = nil
                return .none

            case .changeWindow(let window):
                state.schedule.editor.update(window)
                state.schedule.saveError = nil
                return .none

            case .setInterval(let seconds):
                state.schedule.editor.intervalSeconds = ScheduleEditorState.clamped(seconds)
                state.schedule.saveError = nil
                return .none

            case .setSkipOnBattery(let skip):
                state.schedule.editor.skipOnBattery = skip
                state.schedule.saveError = nil
                return .none

            case .saveSchedule:
                let schedule = state.schedule.editor.schedule
                let tracking = state.schedule.editor.tracking
                return .run { send in
                    do {
                        try ZeitConfig.saveSchedule(schedule, tracking: tracking)
                        await send(.scheduleSaved)
                    } catch {
                        await send(.scheduleSaveFailed(error.localizedDescription))
                    }
                }

            case .scheduleSaved:
                state.schedule.saveError = nil
                return .none

            case .scheduleSaveFailed(let error):
                state.schedule.saveError = error
                return .none

            case .activityTypes:
                return .none

            case .closeSettings:
                state.isCompleted = true
                return .none
            }
        }
    }
}
