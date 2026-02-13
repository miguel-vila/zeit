import Dependencies
import DependenciesMacros
import Foundation
import UserNotifications

// MARK: - Client Interface

@DependencyClient
struct NotificationClient: Sendable {
    /// Show a notification with title, subtitle, and body
    var show: @Sendable (
        _ title: String,
        _ subtitle: String,
        _ body: String
    ) async -> Void
}

// MARK: - Dependency Registration

extension DependencyValues {
    var notificationClient: NotificationClient {
        get { self[NotificationClient.self] }
        set { self[NotificationClient.self] = newValue }
    }
}

// MARK: - Live Implementation

extension NotificationClient: DependencyKey {
    static let liveValue = NotificationClient(
        show: { title, subtitle, body in
            let center = UNUserNotificationCenter.current()

            // Request authorization if needed
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }

            // Create and deliver notification
            let content = UNMutableNotificationContent()
            content.title = title
            content.subtitle = subtitle
            content.body = body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil  // Deliver immediately
            )

            try? await center.add(request)
        }
    )
}
