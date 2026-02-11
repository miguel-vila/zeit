import ComposableArchitecture
import SwiftUI

// Note: @main is in main.swift which decides CLI vs GUI mode
struct ZeitAppGUI: App {
    @State private var store = Store(initialState: MenubarFeature.State()) {
        MenubarFeature()
    }

    var body: some Scene {
        // Menubar app
        MenuBarExtra {
            MenubarView(store: store)
        } label: {
            menubarLabel
        }
        .menuBarExtraStyle(.window)
    }

    @ViewBuilder
    private var menubarLabel: some View {
        // Use SF Symbol based on tracking state
        Image(systemName: store.trackingState.iconName)
            .symbolRenderingMode(.hierarchical)
    }
}
