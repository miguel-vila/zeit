import AppKit
import Dependencies
import DependenciesMacros
import Foundation

// MARK: - App Activation Events

enum AppActivation: Sendable {
    case didBecomeActive
    case willResignActive
}

// MARK: - Client Interface

/// Reads and obtains the macOS permissions Zeit tracks with.
///
/// The checks are made in this process. Zeit is a single TCC subject — the
/// tracker LaunchAgent runs the executable inside the app bundle — so what
/// this process is allowed to do is what the tracking runs are allowed to do.
@DependencyClient
struct PermissionsClient: Sendable {
    /// Whether this process holds `permission`. Never prompts.
    var isGranted: @Sendable (Permission) -> Bool = { _ in false }

    /// Leads the user through granting `permission`, and returns once the
    /// grant lands or the user gives up. See `PermissionGrantGuide`.
    var guideGrant: @Sendable (Permission) async -> Void

    /// Observe app activation events (for re-checking permissions after Settings)
    var observeAppActivation: @Sendable () -> AsyncStream<AppActivation> = { .never }
}

// MARK: - Dependency Registration

extension DependencyValues {
    var permissionsClient: PermissionsClient {
        get { self[PermissionsClient.self] }
        set { self[PermissionsClient.self] = newValue }
    }
}

// MARK: - Live Implementation

extension PermissionsClient: DependencyKey {
    static let liveValue: PermissionsClient = {
        let observer = AppActivationObserver()

        return PermissionsClient(
            isGranted: { permission in
                if permission.isGranted { return true }
                // A Screen Recording grant does not reach a process that was
                // already running, so "no" from this process may be stale.
                guard permission.appliesOnlyToNewProcesses else { return false }
                return PermissionCheckCommand.ask(permission)
            },
            guideGrant: { permission in
                await PermissionGrantGuide.shared.run(permission)
            },
            observeAppActivation: {
                observer.stream
            }
        )
    }()
}

// MARK: - App Activation Observer

private final class AppActivationObserver: @unchecked Sendable {
    private var continuation: AsyncStream<AppActivation>.Continuation?
    let stream: AsyncStream<AppActivation>

    init() {
        var continuation: AsyncStream<AppActivation>.Continuation?
        self.stream = AsyncStream { continuation = $0 }
        self.continuation = continuation

        // Observe app activation
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.continuation?.yield(.didBecomeActive)
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.continuation?.yield(.willResignActive)
        }
    }
}

// MARK: - Convenience

extension PermissionsClient {
    /// The permissions this process holds right now.
    func grantedPermissions() -> Set<Permission> {
        Set(Permission.allCases.filter(isGranted))
    }

    /// Check if all required permissions are granted
    func allPermissionsGranted() -> Bool {
        Permission.allCases.allSatisfy(isGranted)
    }
}
