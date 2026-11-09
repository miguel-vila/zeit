import AppKit
import ComposableArchitecture
import SwiftUI
import UserNotifications

// Note: main.swift decides CLI vs GUI mode and runs ZeitAppDelegate on a plain
// NSApplication. A SwiftUI `App` is deliberately not used: its only scene would
// be an empty `Settings` window that shows up as soon as Zeit is activated.

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

        installMainMenu()
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

    // MARK: - Main Menu

    /// The panels hold text fields, which only get ⌘X/⌘C/⌘V/⌘A/⌘Z from an Edit menu.
    /// There is no menu bar to see (LSUIElement), but the key equivalents still work.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        let quit = NSMenuItem(title: "Quit Zeit", action: #selector(quitZeit), keyEquivalent: "q")
        quit.target = self
        appMenu.addItem(quit)
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
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
            updateStatusItemIcon(
                trackingState: store.trackingState,
                primaryGroupPercentage: store.primaryGroupPercentage
            )
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }

        popover = NSPopover()
        popover.behavior = .transient
        let hosting = NSHostingController(
            rootView: MenubarView(store: store, availableHeight: availableMenubarHeight())
        )
        // The popover's size is set before each showing, from a measurement.
        // Left to SwiftUI, it would be published after the popover is already
        // on screen, and a popover that changes size then keeps the edge it
        // was anchored by and grows off the screen.
        hosting.sizingOptions = []
        popover.contentViewController = hosting
    }

    /// The height the menu's rows need, found by laying a copy of them out.
    /// SwiftUI settles this only once it has laid out, which is too late for a
    /// popover that is already on screen.
    private func menuHeight(availableHeight: CGFloat) -> CGFloat {
        let measuring = NSHostingView(
            rootView: MenubarContentView(store: store, availableHeight: availableHeight)
        )
        measuring.frame = NSRect(x: 0, y: 0, width: MenubarContentView.width, height: 0)
        measuring.layoutSubtreeIfNeeded()
        return measuring.fittingSize.height
    }

    /// How tall the popover's content may be below the menu bar of the screen
    /// that shows the status item, leaving room for the popover's own frame.
    private func availableMenubarHeight() -> CGFloat {
        let screen = statusItem.button?.window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        let visibleHeight = screen?.visibleFrame.height ?? 600
        return visibleHeight - Self.popoverFrameHeight
    }

    /// The popover's border and shadow inset, which sit outside its content.
    private static let popoverFrameHeight: CGFloat = 28

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
            // The status item can move between screens, and the day's figures
            // change between showings, so both the budget and the height are
            // taken again each time the popover opens.
            let availableHeight = availableMenubarHeight()
            (popover.contentViewController as? NSHostingController<MenubarView>)?.rootView =
                MenubarView(store: store, availableHeight: availableHeight)
            popover.contentSize = NSSize(
                width: MenubarContentView.width,
                height: menuHeight(availableHeight: availableHeight)
            )
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Activate so the popover can receive keyboard events
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Right-Click Context Menu

    private func showContextMenu() {
        let menu = NSMenu()
        let quit = NSMenuItem(title: "Quit Zeit", action: #selector(quitZeit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    /// Both ways out of the app go through `.quitApp`, which stops the launchd
    /// job before terminating. Calling `NSApplication.terminate` straight from
    /// here would leave the job running, and launchd would start Zeit again.
    @objc private func quitZeit() {
        store.send(.quitApp)
    }

    func menuDidClose(_: NSMenu) {
        // Reset so left-click goes through the action handler again
        statusItem.menu = nil
    }

    // MARK: - Icon Observation

    private func startIconObservation() {
        withObservationTracking {
            let trackingState = store.trackingState
            let primaryGroupPercentage = store.primaryGroupPercentage
            updateStatusItemIcon(
                trackingState: trackingState,
                primaryGroupPercentage: primaryGroupPercentage
            )
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.startIconObservation()
            }
        }
    }

    private func updateStatusItemIcon(
        trackingState: TrackingState,
        primaryGroupPercentage: Double
    ) {
        guard let button = statusItem.button else { return }

        let percentage = Int(primaryGroupPercentage)

        switch trackingState {
        case .active:
            button.image = renderPercentageWithDot(percentage: percentage, dotColor: .systemGreen)
        case .pausedManual:
            button.image = renderPercentageWithDot(percentage: percentage, dotColor: .systemOrange)
        case .outsideSchedule:
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
        } onChange: { [weak self] in
            Task { @MainActor in
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
        } onChange: { [weak self] in
            Task { @MainActor in
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
        } onChange: { [weak self] in
            Task { @MainActor in
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
        } onChange: { [weak self] in
            Task { @MainActor in
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
