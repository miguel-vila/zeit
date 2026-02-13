import ComposableArchitecture
import Foundation

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

        // Settings
        var launchAtLogin: Bool = false

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
        case quitApp

        // Child feature actions
        case details(PresentationAction<DetailsFeature.Action>)
        case objectives(PresentationAction<ObjectivesFeature.Action>)
        case onboarding(PresentationAction<OnboardingFeature.Action>)
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
                return .none

            case .onboarding:
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
