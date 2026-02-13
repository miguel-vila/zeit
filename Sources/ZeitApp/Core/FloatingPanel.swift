import AppKit
import ComposableArchitecture
import SwiftUI

// MARK: - View Extension

extension View {
    /// Presents content in a standalone floating panel instead of a sheet.
    /// Use this for windows that need to remain open independently of the menubar popover.
    func floatingPanel<ChildState: Equatable, ChildAction, PanelContent: View>(
        item: Binding<Store<ChildState, ChildAction>?>,
        title: String = "",
        @ViewBuilder content: @escaping (Store<ChildState, ChildAction>) -> PanelContent
    ) -> some View {
        modifier(
            FloatingPanelModifier(
                item: item,
                panelTitle: title,
                panelContent: content
            )
        )
    }
}

// MARK: - View Modifier

private struct FloatingPanelModifier<
    ChildState: Equatable, ChildAction, PanelContent: View
>: ViewModifier {
    @Binding var item: Store<ChildState, ChildAction>?
    let panelTitle: String
    @ViewBuilder let panelContent: (Store<ChildState, ChildAction>) -> PanelContent

    @State private var controller = PanelController()

    func body(content: Content) -> some View {
        content
            .onChange(of: item == nil) { wasNil, isNil in
                if !wasNil && isNil {
                    controller.close()
                } else if wasNil && !isNil, let store = item {
                    let view = panelContent(store)
                    controller.open(title: panelTitle, content: view) {
                        item = nil
                    }
                }
            }
    }
}

// MARK: - Panel Controller

private final class PanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var onClose: (() -> Void)?

    func open<Content: View>(
        title: String,
        content: Content,
        onClose: @escaping () -> Void
    ) {
        close()

        self.onClose = onClose

        let hostingView = NSHostingView(rootView: content)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.contentView = hostingView
        panel.center()
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.panel = panel
    }

    func close() {
        guard let p = panel else { return }
        panel = nil
        onClose = nil
        p.close()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_: Notification) {
        let callback = onClose
        panel = nil
        onClose = nil
        callback?()
    }
}
