import ComposableArchitecture
import Foundation

@Reducer
struct PermissionsFeature {
    @ObservableState
    struct State: Equatable {
        var screenRecordingGranted: Bool = false
        var accessibilityGranted: Bool = false

        var allGranted: Bool {
            screenRecordingGranted && accessibilityGranted
        }
    }

    enum Action {
        case task
        case checkPermissions
        case permissionsUpdated(screenRecording: Bool, accessibility: Bool)
        case appBecameActive
        case openScreenRecordingSettings
        case openAccessibilitySettings
        case continuePressed
        case allPermissionsGranted
    }

    @Dependency(\.permissionsClient) var permissions
    @Dependency(\.continuousClock) var clock

    private enum CancelID { case appObserver, refreshTimer }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                return .merge(
                    .send(.checkPermissions),
                    startAppObserver(),
                    startRefreshTimer()
                )

            case .checkPermissions:
                return .run { send in
                    let screen = permissions.screenRecordingStatus() == .granted
                    let accessibility = permissions.accessibilityStatus() == .granted
                    await send(.permissionsUpdated(
                        screenRecording: screen,
                        accessibility: accessibility
                    ))
                }

            case let .permissionsUpdated(screen, accessibility):
                state.screenRecordingGranted = screen
                state.accessibilityGranted = accessibility

                if state.allGranted {
                    return .send(.allPermissionsGranted)
                }
                return .none

            case .appBecameActive:
                // Re-check when user returns from System Settings
                return .send(.checkPermissions)

            case .openScreenRecordingSettings:
                return .run { _ in
                    await permissions.openScreenRecordingSettings()
                }

            case .openAccessibilitySettings:
                return .run { _ in
                    await permissions.openAccessibilitySettings()
                }

            case .continuePressed:
                // Parent handles navigation/dismissal
                return .merge(
                    .cancel(id: CancelID.appObserver),
                    .cancel(id: CancelID.refreshTimer)
                )

            case .allPermissionsGranted:
                // Parent will handle dismissing
                return .merge(
                    .cancel(id: CancelID.appObserver),
                    .cancel(id: CancelID.refreshTimer)
                )
            }
        }
    }

    // MARK: - Helpers

    private func startAppObserver() -> Effect<Action> {
        .run { send in
            for await activation in permissions.observeAppActivation() {
                if case .didBecomeActive = activation {
                    await send(.appBecameActive)
                }
            }
        }
        .cancellable(id: CancelID.appObserver)
    }

    private func startRefreshTimer() -> Effect<Action> {
        .run { send in
            for await _ in clock.timer(interval: .seconds(5)) {
                await send(.checkPermissions)
            }
        }
        .cancellable(id: CancelID.refreshTimer)
    }
}
