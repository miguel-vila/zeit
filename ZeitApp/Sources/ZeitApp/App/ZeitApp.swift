import AppKit
import ComposableArchitecture
import SwiftUI

// Note: @main is in main.swift which decides CLI vs GUI mode
struct ZeitAppGUI: App {
    @NSApplicationDelegateAdaptor(ZeitAppDelegate.self) var appDelegate

    var body: some Scene {
        // No visible window scenes — the menubar is managed by the AppDelegate
        Settings {
            EmptyView()
        }
    }
}

// MARK: - App Delegate

final class ZeitAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    // Onboarding panel — managed here (not in the popover's SwiftUI view)
    // because the popover isn't shown on launch, so its .onChange never fires.
    private var onboardingPanel: NSPanel?
    private var onboardingPanelWindowDelegate: OnboardingPanelWindowDelegate?
    private var onboardingStore: StoreOf<OnboardingFeature>?

    let store = Store(initialState: MenubarFeature.State()) {
        MenubarFeature()
    }

    func applicationDidFinishLaunching(_: Notification) {
        setupStatusItem()
        startIconObservation()
        store.send(.task)
        presentOnboardingIfNeeded()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: store.trackingState.iconName,
                accessibilityDescription: "Zeit"
            )
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenubarView(store: store)
        )
    }

    @objc private func statusItemClicked(_: Any?) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Activate so the popover can receive keyboard events
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Right-Click Context Menu

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(
                title: "Quit Zeit",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    func menuDidClose(_: NSMenu) {
        // Reset so left-click goes through the action handler again
        statusItem.menu = nil
    }

    // MARK: - Icon Observation

    private func startIconObservation() {
        withObservationTracking {
            let iconName = store.trackingState.iconName
            statusItem.button?.image = NSImage(
                systemSymbolName: iconName,
                accessibilityDescription: "Zeit"
            )
        } onChange: {
            Task { @MainActor [weak self] in
                self?.startIconObservation()
            }
        }
    }

    // MARK: - Onboarding Panel

    private func presentOnboardingIfNeeded() {
        guard store.onboarding != nil, onboardingPanel == nil else { return }

        // Standalone store — actions within the panel (skip, continue,
        // permissions granted) set isCompleted which we observe below.
        let childStore = Store(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        }

        let windowDelegate = OnboardingPanelWindowDelegate()
        windowDelegate.onClose = { [weak self] in
            self?.cleanupOnboarding()
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Welcome to Zeit"
        panel.contentView = NSHostingView(rootView: OnboardingView(store: childStore))
        panel.center()
        panel.delegate = windowDelegate
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        onboardingPanel = panel
        onboardingPanelWindowDelegate = windowDelegate
        onboardingStore = childStore

        observeOnboardingCompletion()
    }

    private func observeOnboardingCompletion() {
        guard let childStore = onboardingStore else { return }

        withObservationTracking {
            _ = childStore.isCompleted
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                if childStore.isCompleted {
                    self.onboardingPanelWindowDelegate?.onClose = nil
                    self.onboardingPanel?.close()
                    self.cleanupOnboarding()
                } else {
                    self.observeOnboardingCompletion()
                }
            }
        }
    }

    private func cleanupOnboarding() {
        onboardingPanel = nil
        onboardingPanelWindowDelegate = nil
        onboardingStore = nil
        // Clear the main store's onboarding state
        if store.onboarding != nil {
            store.send(.onboarding(.dismiss))
        }
    }
}

// MARK: - Onboarding Panel Window Delegate

private final class OnboardingPanelWindowDelegate: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?

    func windowWillClose(_: Notification) {
        let callback = onClose
        onClose = nil
        callback?()
    }
}
