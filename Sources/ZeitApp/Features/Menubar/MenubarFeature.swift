import ComposableArchitecture
import Foundation

struct ForceTrackInfo: Equatable {
    let activityName: String
    let description: String
}

#if DEBUG
struct SampleInfo: Equatable {
    let activityName: String
    let samplePath: String
}
#endif

@Reducer
struct MenubarFeature {
    @ObservableState
    struct State: Equatable {
        var trackingState: TrackingState = .pausedManual
        var todayStats: [ActivityStat] = []
        var totalActivities: Int = 0
        var workPercentage: Double = 0
        var todayDate: String = ""
        var dayObjectives: DayObjectives?

        // Child feature states
        @Presents var details: DetailsFeature.State?
        @Presents var objectives: ObjectivesFeature.State?
        @Presents var onboarding: OnboardingFeature.State?
        @Presents var settings: SettingsFeature.State?

        // Settings
        var launchAtLogin: Bool = false

        // Force track
        var isForceTracking: Bool = false

        // Clear today's data
        var isClearingTodayData: Bool = false

        #if DEBUG
        // Sampling
        var isSampling: Bool = false
        var showDelayInput: Bool = false
        #endif

        // Loading state
        var isLoading: Bool = false
    }

    enum Action {
        // Lifecycle
        case task
        case refreshTick
        case refreshData
        case modelsCheckCompleted(allDownloaded: Bool)

        // Data responses
        case dataLoaded(DayRecord?, DayObjectives?)
        case trackingStateUpdated(TrackingState)

        // User actions
        case toggleTracking
        case trackingToggled(Result<Void, Error>)
        case showDetails
        case showObjectives
        case toggleLaunchAtLogin
        case launchAtLoginToggled(Bool)
        case showSettings
        case forceTrack
        case forceTrackCompleted(Result<ForceTrackInfo, Error>)
        case clearTodayData
        case clearTodayDataCompleted(Result<Void, Error>)
        #if DEBUG
        case forceTrackAndSample
        case forceTrackAndSampleWithDelay
        case sampleWithDelayConfirmed(seconds: Int)
        case sampleCompleted(Result<SampleInfo, Error>)
        #endif
        case quitApp

        // Child feature actions
        case details(PresentationAction<DetailsFeature.Action>)
        case objectives(PresentationAction<ObjectivesFeature.Action>)
        case onboarding(PresentationAction<OnboardingFeature.Action>)
        case settings(PresentationAction<SettingsFeature.Action>)
    }

    @Dependency(\.databaseClient) var database
    @Dependency(\.trackingClient) var tracking
    @Dependency(\.launchAgentClient) var launchAgent
    @Dependency(\.notificationClient) var notification
    @Dependency(\.permissionsClient) var permissions
    @Dependency(\.modelClient) var modelClient
    @Dependency(\.continuousClock) var clock

    private enum CancelID { case timer }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                // Initial setup
                state.todayDate = todayString()
                state.launchAtLogin = launchAgent.isMenubarServiceLoaded()

                // Show onboarding if permissions aren't granted
                if !permissions.allPermissionsGranted() {
                    state.onboarding = OnboardingFeature.State()
                }

                return .merge(
                    .send(.refreshData),
                    startRefreshTimer(),
                    .run { send in
                        let allDownloaded = await modelClient.allModelsDownloaded()
                        await send(.modelsCheckCompleted(allDownloaded: allDownloaded))
                    },
                    // Reload tracker service to reset any launchd throttle from prior failures
                    .run { _ in
                        try? await launchAgent.reloadTrackerService()
                    }
                )

            case .modelsCheckCompleted(let allDownloaded):
                // If models aren't downloaded and onboarding isn't already showing,
                // show onboarding starting at the model download step
                if !allDownloaded && state.onboarding == nil {
                    var onboardingState = OnboardingFeature.State()
                    onboardingState.step = .modelDownload
                    state.onboarding = onboardingState
                }
                return .none

            case .refreshTick:
                // Update tracking state and refresh data periodically
                state.trackingState = tracking.getTrackingState()
                return .send(.refreshData)

            case .refreshData:
                let today = todayString()
                state.todayDate = today
                state.isLoading = true

                return .run { send in
                    let record = try? await database.getDayRecord(today)
                    let objectives = try? await database.getDayObjectives(today)
                    await send(.dataLoaded(record, objectives))
                }

            case .dataLoaded(let record, let objectives):
                state.isLoading = false
                state.trackingState = tracking.getTrackingState()
                state.dayObjectives = objectives

                if let record {
                    state.totalActivities = record.count
                    state.todayStats = computeActivityBreakdown(from: record.activities)
                    state.workPercentage = workPercentage(from: state.todayStats)
                } else {
                    state.totalActivities = 0
                    state.todayStats = []
                    state.workPercentage = 0
                }
                return .none

            case .trackingStateUpdated(let newState):
                state.trackingState = newState
                return .none

            case .toggleTracking:
                guard state.trackingState.canToggle else {
                    // Can't toggle outside work hours
                    return .run { _ in
                        await notification.show(
                            "Zeit",
                            "Cannot Toggle",
                            "Tracking cannot be toggled outside work hours"
                        )
                    }
                }

                let isActive = state.trackingState.isActive

                return .run { send in
                    do {
                        if isActive {
                            try await tracking.stopTracking()
                            await notification.show("Zeit", "Stopped", "Tracking has been paused")
                        } else {
                            try await tracking.startTracking()
                            await notification.show("Zeit", "Resumed", "Tracking has been resumed")
                        }
                        await send(.trackingToggled(.success(())))
                    } catch {
                        await send(.trackingToggled(.failure(error)))
                    }
                }

            case .trackingToggled(.success):
                state.trackingState = tracking.getTrackingState()
                return .none

            case .trackingToggled(.failure(let error)):
                return .run { _ in
                    await notification.show(
                        "Zeit Error",
                        "Toggle Failed",
                        error.localizedDescription
                    )
                }

            case .showDetails:
                guard state.totalActivities > 0 else {
                    return .run { [date = state.todayDate] _ in
                        await notification.show(
                            "Zeit",
                            "No Data",
                            "No activities tracked for \(date)"
                        )
                    }
                }
                state.details = DetailsFeature.State(
                    date: state.todayDate,
                    stats: state.todayStats,
                    totalActivities: state.totalActivities
                )
                return .none

            case .showObjectives:
                state.objectives = ObjectivesFeature.State(date: state.todayDate)
                return .none

            case .showSettings:
                state.settings = SettingsFeature.State()
                return .none

            case .forceTrack:
                guard !state.isForceTracking else { return .none }
                state.isForceTracking = true

                return .run { send in
                    do {
                        let config = ZeitConfig.load()
                        let identifier = ActivityIdentifier(
                            visionModel: config.models.vision,
                            textModel: config.models.text.model,
                            textProvider: config.models.text.provider
                        )
                        let result = try await identifier.identifyCurrentActivity()
                        let entry = result.toActivityEntry()
                        let db = try DatabaseHelper()
                        try await db.insertActivity(entry)
                        await send(.forceTrackCompleted(.success(
                            ForceTrackInfo(
                                activityName: result.activity.displayName,
                                description: result.description
                            )
                        )))
                    } catch {
                        await send(.forceTrackCompleted(.failure(error)))
                    }
                }

            case .forceTrackCompleted(.success(let info)):
                state.isForceTracking = false
                return .merge(
                    .send(.refreshData),
                    .run { _ in
                        await notification.show(
                            "Zeit",
                            info.activityName,
                            info.description
                        )
                    }
                )

            case .forceTrackCompleted(.failure(let error)):
                state.isForceTracking = false
                return .run { _ in
                    await notification.show(
                        "Zeit Error",
                        "Force Track Failed",
                        error.localizedDescription
                    )
                }

            case .clearTodayData:
                guard !state.isClearingTodayData else { return .none }
                state.isClearingTodayData = true
                let today = todayString()

                return .run { send in
                    do {
                        _ = try await database.deleteDayActivities(today)
                        await send(.clearTodayDataCompleted(.success(())))
                    } catch {
                        await send(.clearTodayDataCompleted(.failure(error)))
                    }
                }

            case .clearTodayDataCompleted(.success):
                state.isClearingTodayData = false
                return .merge(
                    .send(.refreshData),
                    .run { _ in
                        await notification.show(
                            "Zeit",
                            "Data Cleared",
                            "Today's activity data has been cleared"
                        )
                    }
                )

            case .clearTodayDataCompleted(.failure(let error)):
                state.isClearingTodayData = false
                return .run { _ in
                    await notification.show(
                        "Zeit Error",
                        "Clear Failed",
                        error.localizedDescription
                    )
                }

            #if DEBUG
            case .forceTrackAndSample:
                guard !state.isSampling else { return .none }
                state.isSampling = true

                return .run { send in
                    do {
                        let config = ZeitConfig.load()
                        let identifier = ActivityIdentifier(
                            visionModel: config.models.vision,
                            textModel: config.models.text.model,
                            textProvider: config.models.text.provider
                        )
                        let result = try await identifier.identifyCurrentActivity(sample: true)
                        let entry = result.toActivityEntry()
                        let db = try DatabaseHelper()
                        try await db.insertActivity(entry)
                        // The sample directory path is printed by identifyCurrentActivity
                        await send(.sampleCompleted(.success(
                            SampleInfo(
                                activityName: result.activity.displayName,
                                samplePath: ""
                            )
                        )))
                    } catch {
                        await send(.sampleCompleted(.failure(error)))
                    }
                }

            case .forceTrackAndSampleWithDelay:
                state.showDelayInput = true
                return .none

            case .sampleWithDelayConfirmed(let seconds):
                state.showDelayInput = false
                guard !state.isSampling else { return .none }
                state.isSampling = true

                // Save delay for next time
                UserDefaults.standard.set(seconds, forKey: "lastSampleDelay")

                return .run { send in
                    do {
                        if seconds > 0 {
                            try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                        }
                        let config = ZeitConfig.load()
                        let identifier = ActivityIdentifier(
                            visionModel: config.models.vision,
                            textModel: config.models.text.model,
                            textProvider: config.models.text.provider
                        )
                        let result = try await identifier.identifyCurrentActivity(sample: true)
                        let entry = result.toActivityEntry()
                        let db = try DatabaseHelper()
                        try await db.insertActivity(entry)
                        await send(.sampleCompleted(.success(
                            SampleInfo(
                                activityName: result.activity.displayName,
                                samplePath: ""
                            )
                        )))
                    } catch {
                        await send(.sampleCompleted(.failure(error)))
                    }
                }

            case .sampleCompleted(.success(let info)):
                state.isSampling = false
                return .merge(
                    .send(.refreshData),
                    .run { _ in
                        await notification.show(
                            "Zeit",
                            "Sample: \(info.activityName)",
                            "Sample saved to ~/.local/share/zeit/samples/"
                        )
                    }
                )

            case .sampleCompleted(.failure(let error)):
                state.isSampling = false
                return .run { _ in
                    await notification.show(
                        "Zeit Error",
                        "Sample Failed",
                        error.localizedDescription
                    )
                }
            #endif

            case .toggleLaunchAtLogin:
                let currentlyEnabled = state.launchAtLogin

                return .run { send in
                    do {
                        if currentlyEnabled {
                            try await launchAgent.unloadMenubarService()
                            await notification.show(
                                "Zeit",
                                "Launch at Login",
                                "Disabled - Zeit won't start automatically"
                            )
                        } else {
                            try await launchAgent.loadMenubarService()
                            await notification.show(
                                "Zeit",
                                "Launch at Login",
                                "Enabled - Zeit will start automatically"
                            )
                        }
                        await send(.launchAtLoginToggled(!currentlyEnabled))
                    } catch {
                        await notification.show(
                            "Zeit Error",
                            "Toggle Failed",
                            error.localizedDescription
                        )
                    }
                }

            case .launchAtLoginToggled(let enabled):
                state.launchAtLogin = enabled
                return .none

            case .quitApp:
                return .run { _ in
                    await MainActor.run {
                        NSApplication.shared.terminate(nil)
                    }
                }

            case .details:
                return .none

            case .objectives(.presented(.saved)):
                // Refresh data after objectives are saved
                return .send(.refreshData)

            case .objectives:
                return .none

            case .onboarding(.presented(.completed)):
                state.onboarding = nil
                return .run { _ in
                    do {
                        try await launchAgent.installServices()
                        try await launchAgent.loadTrackerService()
                    } catch {
                        await notification.show(
                            "Zeit",
                            "Service Setup",
                            "Could not start tracker service: \(error.localizedDescription)"
                        )
                    }
                }

            case .onboarding(.dismiss):
                return .none

            case .onboarding:
                return .none

            case .settings(.presented(.closeSettings)):
                state.settings = nil
                return .none

            case .settings(.dismiss):
                return .none

            case .settings:
                return .none
            }
        }
        .ifLet(\.$details, action: \.details) {
            DetailsFeature()
        }
        .ifLet(\.$objectives, action: \.objectives) {
            ObjectivesFeature()
        }
        .ifLet(\.$onboarding, action: \.onboarding) {
            OnboardingFeature()
        }
        .ifLet(\.$settings, action: \.settings) {
            SettingsFeature()
        }
    }

    // MARK: - Helpers

    private func startRefreshTimer() -> Effect<Action> {
        .run { send in
            for await _ in clock.timer(interval: .seconds(60)) {
                await send(.refreshTick)
            }
        }
        .cancellable(id: CancelID.timer)
    }

    private func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

// MARK: - NSApplication import for quit

import AppKit
