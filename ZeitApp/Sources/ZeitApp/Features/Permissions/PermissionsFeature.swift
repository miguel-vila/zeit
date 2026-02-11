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
        case skip
        case continuePressed
        case allPermissionsGranted
    }

    @Dependency(\.permissionsClient) var permissions
    @Dependency(\.dismiss) var dismiss

    private enum CancelID { case appObserver }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                return .merge(
                    .send(.checkPermissions),
                    startAppObserver()
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

            case .skip:
                return .merge(
                    .cancel(id: CancelID.appObserver),
                    .run { _ in
                        await dismiss()
                    }
                )

            case .continuePressed:
                return .merge(
                    .cancel(id: CancelID.appObserver),
                    .run { _ in
                        await dismiss()
                    }
                )

            case .allPermissionsGranted:
                // Parent will handle dismissing
                return .cancel(id: CancelID.appObserver)
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
}
