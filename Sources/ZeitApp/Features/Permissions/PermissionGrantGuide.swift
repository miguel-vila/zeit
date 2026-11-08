import AppKit
import SwiftUI

/// Leads the user through granting one permission.
///
/// Opening the System Settings pane is only half the job: the pane lists the
/// apps that already hold the permission, and Zeit is not among them, so the
/// user is left searching for something that is not there. This floats a
/// borderless panel over the System Settings window holding a drag source for
/// Zeit, because dropping an app on a privacy list both adds it and switches
/// it on. The panel follows the window and goes away once the grant lands.
@MainActor
final class PermissionGrantGuide {
    static let shared = PermissionGrantGuide()

    private var panel: NSPanel?
    private var closedByUser = false

    private init() {}

    /// Opens the pane for `permission` and floats the drag source over it.
    /// Returns once the permission is granted or the user closes the panel.
    /// Starting a second guide replaces the first.
    func run(_ permission: Permission) async {
        dismiss()

        if !permission.isGranted {
            // An entry left by an earlier install swallows the drop, so it has
            // to go before the user is sent to the list. See clearListEntry().
            await Task.detached { permission.clearListEntry() }.value
        }
        permission.openSettings()

        closedByUser = false
        let panel = makePanel(for: permission)
        self.panel = panel

        for await settingsFrame in SystemSettingsWindow.frames() {
            guard !closedByUser, !permission.isGranted, self.panel === panel else { break }

            if let settingsFrame, settingsFrame.width > 0 {
                panel.setFrame(Self.panelFrame(over: settingsFrame), display: true)
                panel.orderFrontRegardless()
            } else {
                // System Settings is closed, minimised or on another Space.
                panel.orderOut(nil)
            }
        }

        if self.panel === panel {
            dismiss()
        }
    }

    func dismiss() {
        panel?.close()
        panel = nil
    }

    // MARK: - Panel

    private func makePanel(for permission: Permission) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 110),
            // Non-activating keeps System Settings in front and focused, so
            // the drop target stays live while the panel is on top of it.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let view = PermissionDropPanelView(permission: permission) { [weak self] in
            self?.closedByUser = true
        }
        let hosting = NSHostingView(rootView: view)
        hosting.frame = panel.contentLayoutRect
        panel.contentView = hosting

        return panel
    }

    /// Sits inside the bottom edge of the System Settings window, where it
    /// covers the least of the list the user is dragging into.
    private static func panelFrame(over settingsFrame: CGRect) -> CGRect {
        let margin: CGFloat = 12
        let height: CGFloat = 110
        let width = max(360, settingsFrame.width - margin * 2)
        return CGRect(
            x: settingsFrame.midX - width / 2,
            y: settingsFrame.minY + margin,
            width: width,
            height: height
        )
    }
}
