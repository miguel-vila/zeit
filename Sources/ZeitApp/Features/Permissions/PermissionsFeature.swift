import ComposableArchitecture
import Foundation

@Reducer
struct PermissionsFeature {
    @ObservableState
    struct State: Equatable {
        var granted: Set<Permission> = []

        /// The permission the drop panel is currently open for, if any.
        var guiding: Permission?

        var allGranted: Bool {
            Permission.allCases.allSatisfy(granted.contains)
        }
    }

    enum Action {
        case task
        case checkPermissions
        case permissionsUpdated(Set<Permission>)
        case appBecameActive
        case grantRequested(Permission)
        case guideFinished
        case continuePressed
        case allPermissionsGranted
    }

    @Dependency(\.permissionsClient) var permissions
    @Dependency(\.continuousClock) var clock

    private enum CancelID { case appObserver, refreshTimer, guide }

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
                    await send(.permissionsUpdated(permissions.grantedPermissions()))
                }

            case let .permissionsUpdated(granted):
                state.granted = granted

                if state.allGranted {
                    return .send(.allPermissionsGranted)
                }
                return .none

            case .appBecameActive:
                // Re-check when user returns from System Settings
                return .send(.checkPermissions)

            case let .grantRequested(permission):
                state.guiding = permission
                return .run { send in
                    await permissions.guideGrant(permission)
                    await send(.guideFinished)
                }
                .cancellable(id: CancelID.guide, cancelInFlight: true)

            case .guideFinished:
                state.guiding = nil
                return .send(.checkPermissions)

            case .continuePressed:
                // Parent handles navigation/dismissal
                return stopWork()

            case .allPermissionsGranted:
                // Only a signal to the parent, which decides whether to move
                // on. The Settings tab stays on this screen and keeps polling,
                // so that a grant revoked later still shows up.
                return .none
            }
        }
    }

    // MARK: - Helpers

    private func stopWork() -> Effect<Action> {
        .merge(
            .cancel(id: CancelID.appObserver),
            .cancel(id: CancelID.refreshTimer),
            .cancel(id: CancelID.guide)
        )
    }

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
