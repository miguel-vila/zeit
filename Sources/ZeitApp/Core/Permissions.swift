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

    /// The name the privacy database gives this permission, which is the name
    /// `tccutil` takes.
    private var tccServiceName: String {
        switch self {
        case .screenRecording: "ScreenCapture"
        case .accessibility: "Accessibility"
        }
    }

    /// The `tccutil` arguments that take `bundleIdentifier` out of this
    /// permission's list.
    func listRemovalArguments(for bundleIdentifier: String) -> [String] {
        ["reset", tccServiceName, bundleIdentifier]
    }

    /// Takes Zeit out of this permission's list.
    ///
    /// An entry in a privacy list is tied to the exact binary that was
    /// granted — Zeit is signed ad-hoc, so its designated requirement is a
    /// bare cdhash — and every build produces a different binary. After a
    /// reinstall the entry matches nothing, and System Settings ignores a drop
    /// of an app it already lists, so the dead entry blocks every further
    /// attempt to grant. Removing it is what makes the drop land.
    ///
    /// Only for a permission Zeit does not hold: then there is no live grant
    /// to lose, and an entry that is already absent is not an error.
    func clearListEntry() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

        let tccutil = Process()
        tccutil.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        tccutil.arguments = listRemovalArguments(for: bundleIdentifier)
        tccutil.standardOutput = FileHandle.nullDevice
        tccutil.standardError = FileHandle.nullDevice

        do {
            try tccutil.run()
            tccutil.waitUntilExit()
        } catch {
            // The entry stays, and the user removes it by hand as before.
        }
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
