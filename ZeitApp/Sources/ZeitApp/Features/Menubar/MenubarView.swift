import ComposableArchitecture
import SwiftUI

struct MenubarView: View {
    @Bindable var store: StoreOf<MenubarFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerSection

            Divider()

            // Activity stats
            if store.totalActivities > 0 {
                statsSection
                Divider()
            }

            // Actions
            actionsSection

            Divider()

            // Settings
            settingsSection

            Divider()

            // Quit
            Button("Quit Zeit") {
                store.send(.quitApp)
            }
            .keyboardShortcut("q")
        }
        .frame(minWidth: 280)
        .task {
            await store.send(.task).finish()
        }
        .sheet(item: $store.scope(state: \.details, action: \.details)) { detailsStore in
            DetailsView(store: detailsStore)
        }
        .sheet(item: $store.scope(state: \.objectives, action: \.objectives)) { objectivesStore in
            ObjectivesView(store: objectivesStore)
        }
        .sheet(item: $store.scope(state: \.permissions, action: \.permissions)) { permissionsStore in
            PermissionsView(store: permissionsStore)
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(store.todayDate)
                    .font(.headline)
                if store.totalActivities > 0 {
                    Text("(\(store.totalActivities) activities)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Image(systemName: store.trackingState.iconName)
                    .foregroundStyle(iconColor)
                Text(store.trackingState.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Work percentage
            HStack {
                Text("Work activities:")
                Spacer()
                Text("\(Int(store.workPercentage))%")
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 12)

            // Activity breakdown
            ForEach(store.todayStats.prefix(5)) { stat in
                HStack {
                    Circle()
                        .fill(stat.activity.isWork ? Color.green : Color.blue)
                        .frame(width: 8, height: 8)
                    Text(stat.activity.displayName)
                        .font(.caption)
                    Spacer()
                    Text("\(String(format: "%.1f", stat.percentage))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("(\(stat.count) min)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
            }

            if store.todayStats.count > 5 {
                Text("+ \(store.todayStats.count - 5) more...")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 8)
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Toggle tracking
            Button {
                store.send(.toggleTracking)
            } label: {
                HStack {
                    Image(systemName: store.trackingState.isActive ? "pause.fill" : "play.fill")
                    Text(store.trackingState.isActive ? "Stop Tracking" : "Resume Tracking")
                }
            }
            .disabled(!store.trackingState.canToggle)

            Button {
                store.send(.refreshData)
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                }
            }

            Button {
                store.send(.showDetails)
            } label: {
                HStack {
                    Image(systemName: "chart.bar")
                    Text("View Details")
                }
            }

            Button {
                store.send(.showObjectives)
            } label: {
                HStack {
                    Image(systemName: "target")
                    Text("Set Day Objectives")
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var settingsSection: some View {
        Toggle("Launch at Login", isOn: Binding(
            get: { store.launchAtLogin },
            set: { _ in store.send(.toggleLaunchAtLogin) }
        ))
        .toggleStyle(.checkbox)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private var iconColor: Color {
        switch store.trackingState {
        case .active:
            return .green
        case .pausedManual:
            return .orange
        case .outsideWorkHours:
            return .purple
        }
    }
}
