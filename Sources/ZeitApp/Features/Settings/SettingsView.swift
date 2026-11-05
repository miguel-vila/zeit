import ComposableArchitecture
import SwiftUI

struct SettingsView: View {
    @Bindable var store: StoreOf<SettingsFeature>

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .frame(minWidth: 740, minHeight: 540)
        .task {
            await store.send(.task).finish()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(SettingsFeature.State.Tab.allCases, id: \.self, selection: Binding(
            get: { store.selectedTab },
            set: { tab in
                if let tab { store.send(.selectTab(tab)) }
            }
        )) { tab in
            Label(tab.rawValue, systemImage: tab.icon)
        }
        .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 200)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        switch store.selectedTab {
        case .permissions:
            settingsPermissionsTab
        case .models:
            settingsModelsTab
        case .schedule:
            settingsScheduleTab
        case .activityTypes:
            settingsActivityTypesTab
        case .about:
            settingsAboutTab
        }
    }

    // MARK: - Permissions Tab

    private var settingsPermissionsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Permissions")
                .font(.title2)
                .fontWeight(.bold)

            Text("Required permissions for Zeit to function properly.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            VStack(spacing: 8) {
                SettingsPermissionRow(
                    name: "Screen Recording",
                    icon: "camera.fill",
                    description: "Required to capture screenshots for activity tracking",
                    isGranted: store.permissions.screenRecordingGranted
                )

                SettingsPermissionRow(
                    name: "Accessibility",
                    icon: "hand.point.up.fill",
                    description: "Required to detect which window is currently active",
                    isGranted: store.permissions.accessibilityGranted
                )
            }

            Spacer()
        }
        .padding(22)
    }

    // MARK: - Models Tab

    private var settingsModelsTab: some View {
        ModelDownloadView(
            store: store.scope(state: \.models, action: \.models),
            mode: .settings
        )
    }

    // MARK: - Schedule Tab

    private var settingsScheduleTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Schedule")
                .font(.title2)
                .fontWeight(.bold)

            Text("Track always, or only inside a list of windows. A moment is tracked when any window contains it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            ScrollView {
                ScheduleEditorView(
                    state: store.schedule.editor,
                    onSetAlways: { store.send(.setAlways($0)) },
                    onAddWindow: { store.send(.addWindow) },
                    onRemoveWindow: { store.send(.removeWindow($0)) },
                    onChangeWindow: { store.send(.changeWindow($0)) },
                    onSetInterval: { store.send(.setInterval($0)) },
                    onSetSkipOnBattery: { store.send(.setSkipOnBattery($0)) },
                    onSetDayStartHour: { store.send(.setDayStartHour($0)) }
                )
            }

            if let error = store.schedule.saveError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Save") {
                    store.send(.saveSchedule)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
    }

    // MARK: - Activity Types Tab

    private var settingsActivityTypesTab: some View {
        // Save belongs to the view's own action bar. As an overlay it sat
        // outside the layout and covered the selection counter.
        ActivityTypesView(
            store: store.scope(state: \.activityTypes, action: \.activityTypes)
        )
    }

    // MARK: - About Tab

    private var settingsAboutTab: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "clock.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            Text("Zeit")
                .font(.title)
                .fontWeight(.bold)

            Text("Version 0.2.0")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Activity tracker for macOS")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(22)
    }
}

// MARK: - Permission Row (read-only)

private struct SettingsPermissionRow: View {
    let name: String
    let icon: String
    let description: String
    let isGranted: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isGranted ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                    .frame(width: 36, height: 36)

                Image(systemName: isGranted ? "checkmark.circle.fill" : icon)
                    .foregroundStyle(isGranted ? .green : .secondary)
                    .font(.body)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isGranted {
                Text("Granted")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.green)
            } else {
                Text("Not Granted")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.red)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.015))
        )
    }
}

