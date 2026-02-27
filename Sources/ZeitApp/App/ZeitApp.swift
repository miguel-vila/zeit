import AppKit
import ComposableArchitecture
import SwiftUI
import UserNotifications

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
    private var onboardingPanelWindowDelegate: PanelWindowDelegate?
    private var onboardingStore: StoreOf<OnboardingFeature>?

    // Settings panel — also managed here for the same reason as onboarding.
    private var settingsPanel: NSPanel?
    private var settingsPanelWindowDelegate: PanelWindowDelegate?
    private var settingsStore: StoreOf<SettingsFeature>?

    let store = Store(initialState: MenubarFeature.State()) {
        MenubarFeature()
    }

    func applicationDidFinishLaunching(_: Notification) {
        // Resume tracking on launch (clear any stop flag left by a previous quit)
        resumeTrackingOnLaunch()

        // Register notification delegate for handling click actions
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared

        setupStatusItem()
        startIconObservation()
        startOnboardingObservation()
        startSettingsObservation()
        store.send(.task)
        presentOnboardingIfNeeded()
    }

    func applicationWillTerminate(_: Notification) {
        // Stop background tracking when the menubar app exits
        stopTrackingOnQuit()
    }

    // MARK: - Tracking Lifecycle

    private static let stopFlagPath: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/zeit/.zeit_stop")

    /// Creates the stop flag so the launchd tracker skips captures while the app is not running.
    private func stopTrackingOnQuit() {
        FileManager.default.createFile(atPath: Self.stopFlagPath.path, contents: nil)
    }

    /// Removes the stop flag so tracking resumes when the app starts.
    private func resumeTrackingOnLaunch() {
        let path = Self.stopFlagPath.path
        if FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            updateStatusItemIcon(trackingState: store.trackingState, workPercentage: store.workPercentage)
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
            let trackingState = store.trackingState
            let workPercentage = store.workPercentage
            updateStatusItemIcon(trackingState: trackingState, workPercentage: workPercentage)
        } onChange: {
            Task { @MainActor [weak self] in
                self?.startIconObservation()
            }
        }
    }

    private func updateStatusItemIcon(trackingState: TrackingState, workPercentage: Double) {
        guard let button = statusItem.button else { return }

        let percentage = Int(workPercentage)

        switch trackingState {
        case .beforeWorkHours:
            button.image = NSImage(
                systemSymbolName: "sun.max.fill",
                accessibilityDescription: "Zeit - Before Work Hours"
            )
        case .active:
            button.image = renderPercentageWithDot(percentage: percentage, dotColor: .systemGreen)
        case .pausedManual:
            button.image = renderPercentageWithDot(percentage: percentage, dotColor: .systemOrange)
        case .afterWorkHours:
            button.image = renderPercentageWithSymbol(
                percentage: percentage,
                symbolName: "moon.fill"
            )
        }
    }

    /// Renders a percentage text with a small colored dot indicator.
    private func renderPercentageWithDot(percentage: Int, dotColor: NSColor) -> NSImage {
        let text = "\(percentage)%"
        let height: CGFloat = 16
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.headerTextColor,
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let dotDiameter: CGFloat = 5
        let dotSpacing: CGFloat = 3
        let width = textSize.width + dotSpacing + dotDiameter + 2

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            // Draw percentage text
            let textRect = NSRect(
                x: 0,
                y: (rect.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            (text as NSString).draw(in: textRect, withAttributes: attributes)

            // Draw colored dot
            let dotRect = NSRect(
                x: textSize.width + dotSpacing,
                y: (rect.height - dotDiameter) / 2,
                width: dotDiameter,
                height: dotDiameter
            )
            dotColor.setFill()
            NSBezierPath(ovalIn: dotRect).fill()

            return true
        }
        // Not template — we need the colored dot to render in color
        image.isTemplate = false
        return image
    }

    /// Renders a percentage text with an SF Symbol next to it.
    private func renderPercentageWithSymbol(percentage: Int, symbolName: String) -> NSImage {
        let text = "\(percentage)%"
        let height: CGFloat = 16
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.headerTextColor,
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        let symbolImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig)

        let symbolSize = symbolImage?.size ?? NSSize(width: 12, height: 12)
        let symbolSpacing: CGFloat = 3
        let width = textSize.width + symbolSpacing + symbolSize.width + 2

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            // Draw percentage text
            let textRect = NSRect(
                x: 0,
                y: (rect.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            (text as NSString).draw(in: textRect, withAttributes: attributes)

            // Draw symbol
            if let symbolImage {
                let symbolRect = NSRect(
                    x: textSize.width + symbolSpacing,
                    y: (rect.height - symbolSize.height) / 2,
                    width: symbolSize.width,
                    height: symbolSize.height
                )
                symbolImage.draw(in: symbolRect)
            }

            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - Onboarding Panel

    private func startOnboardingObservation() {
        withObservationTracking {
            _ = store.onboarding
        } onChange: {
            Task { @MainActor [weak self] in
                self?.presentOnboardingIfNeeded()
                self?.startOnboardingObservation()
            }
        }
    }

    private func presentOnboardingIfNeeded() {
        guard store.onboarding != nil, onboardingPanel == nil else { return }

        // Standalone store — actions within the panel (skip, continue,
        // permissions granted) set isCompleted which we observe below.
        let childStore = Store(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        }

        let windowDelegate = PanelWindowDelegate()
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

    // MARK: - Settings Panel

    private func startSettingsObservation() {
        withObservationTracking {
            _ = store.settings
        } onChange: {
            Task { @MainActor [weak self] in
                self?.presentSettingsIfNeeded()
                self?.startSettingsObservation()
            }
        }
    }

    private func presentSettingsIfNeeded() {
        guard store.settings != nil, settingsPanel == nil else { return }

        let childStore = Store(initialState: SettingsFeature.State()) {
            SettingsFeature()
        }

        let windowDelegate = PanelWindowDelegate()
        windowDelegate.onClose = { [weak self] in
            self?.cleanupSettings()
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Zeit Settings"
        panel.contentView = NSHostingView(rootView: SettingsView(store: childStore))
        panel.center()
        panel.delegate = windowDelegate
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        settingsPanel = panel
        settingsPanelWindowDelegate = windowDelegate
        settingsStore = childStore

        observeSettingsCompletion()
    }

    private func observeSettingsCompletion() {
        guard let childStore = settingsStore else { return }

        withObservationTracking {
            _ = childStore.isCompleted
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                if childStore.isCompleted {
                    self.settingsPanelWindowDelegate?.onClose = nil
                    self.settingsPanel?.close()
                    self.cleanupSettings()
                } else {
                    self.observeSettingsCompletion()
                }
            }
        }
    }

    private func cleanupSettings() {
        settingsPanel = nil
        settingsPanelWindowDelegate = nil
        settingsStore = nil
        // Clear the main store's settings state
        if store.settings != nil {
            store.send(.settings(.dismiss))
        }
    }
}

// MARK: - Panel Window Delegate

private final class PanelWindowDelegate: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?

    func windowWillClose(_: Notification) {
        let callback = onClose
        onClose = nil
        callback?()
    }
}
