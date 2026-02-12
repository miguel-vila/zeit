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

    let store = Store(initialState: MenubarFeature.State()) {
        MenubarFeature()
    }

    func applicationDidFinishLaunching(_: Notification) {
        setupStatusItem()
        startIconObservation()
        store.send(.task)
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
}
