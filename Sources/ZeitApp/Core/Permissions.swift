import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// A macOS privacy permission Zeit needs, with everything that differs between
/// them: how the grant is read, where the user grants it, and whether a grant
/// reaches a process that is already running.
///
/// Zeit is one TCC subject. The tracker LaunchAgent runs the executable inside
/// the app bundle, so a grant to the bundle covers both the menubar app and the
/// tracking runs; nothing has to be granted twice. A `zeit` command typed into
/// a terminal is the exception — macOS attributes it to the terminal, which
/// holds its own grants.
enum Permission: String, CaseIterable, Sendable {
    case screenRecording
    case accessibility

    var displayName: String {
        switch self {
        case .screenRecording: "Screen Recording"
        case .accessibility: "Accessibility"
        }
    }

    /// Why Zeit needs the permission, in the user's terms.
    var reason: String {
        switch self {
        case .screenRecording: "Capture the screenshots that activity tracking reads"
        case .accessibility: "Read which window is in front"
        }
    }

    var iconName: String {
        switch self {
        case .screenRecording: "camera.fill"
        case .accessibility: "hand.point.up.fill"
        }
    }

    /// Whether this process holds the permission. Never prompts.
    var isGranted: Bool {
        switch self {
        case .screenRecording: CGPreflightScreenCaptureAccess()
        case .accessibility: AXIsProcessTrusted()
        }
    }

    /// macOS applies a new Screen Recording grant only to processes started
    /// after the grant, so a running process cannot see one it has just been
    /// given. Zeit never has to restart over this — each tracking run is a new
    /// process launchd starts — but the menubar app does have to ask a new
    /// process what it is allowed to do. See `PermissionCheckCommand`.
    var appliesOnlyToNewProcesses: Bool {
        self == .screenRecording
    }

    /// The System Settings pane listing the apps that hold this permission.
    /// Dropping an app bundle on that list grants it, which is what
    /// `PermissionGrantGuide` leads the user to do.
    var settingsURL: URL {
        let pane: String
        switch self {
        case .screenRecording: pane = "Privacy_ScreenCapture"
        case .accessibility: pane = "Privacy_Accessibility"
        }
        // Force-unwrapped: the components are literals, so this cannot fail.
        return URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(pane)")!
    }

    @MainActor
    func openSettings() {
        NSWorkspace.shared.open(settingsURL)
    }

    /// The file the user adds to a privacy list to grant this process: the app
    /// bundle when Zeit runs from one, and the bare executable otherwise, as in
    /// a development build run straight from `.build`.
    static var tccSubject: URL {
        let bundle = Bundle.main.bundleURL
        if bundle.pathExtension == "app" {
            return bundle
        }
        return URL(fileURLWithPath: Bundle.main.executablePath ?? bundle.path)
    }
}
