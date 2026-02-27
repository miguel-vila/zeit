import ComposableArchitecture
import SwiftUI

struct MenubarView: View {
    @Bindable var store: StoreOf<MenubarFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerSection

            Divider()
                .padding(.horizontal, 12)

            // Day objectives
            if let objectives = store.dayObjectives {
                objectivesSection(objectives)
                Divider()
                    .padding(.horizontal, 12)
            }

            // Activity stats
            if store.totalActivities > 0 {
                statsSection
                Divider()
                    .padding(.horizontal, 12)
            }

            // Actions
            actionsSection

            // Debug (debug builds only)
            debugSection

            Divider()
                .padding(.horizontal, 12)

            // Settings
            settingsSection

            Divider()
                .padding(.horizontal, 12)

            // Quit
            MenubarActionButton(
                icon: "power",
                label: "Quit Zeit",
                action: { store.send(.quitApp) }
            )
            .keyboardShortcut("q")
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .frame(minWidth: 300)
        .floatingPanel(
            item: $store.scope(state: \.details, action: \.details),
            title: "Activity Summary"
        ) { detailsStore in
            DetailsView(store: detailsStore)
        }
        .floatingPanel(
            item: $store.scope(state: \.objectives, action: \.objectives),
            title: "Day Objectives"
        ) { objectivesStore in
            ObjectivesView(store: objectivesStore)
        }
        // Note: onboarding panel is managed by ZeitAppDelegate directly,
        // since the popover's view isn't active on app launch.
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(store.todayDate)
                    .font(.headline)
                Spacer()
                if store.totalActivities > 0 {
                    Text("\(store.totalActivities) activities")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(iconColor)
                    .frame(width: 7, height: 7)
                Text(store.trackingState.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Work percentage with inline bar
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Work")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(store.workPercentage))%")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.quaternary)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.accentColor.opacity(0.7))
                            .frame(
                                width: max(0, geometry.size.width * store.workPercentage / 100)
                            )
                    }
                }
                .frame(height: 5)
            }
            .padding(.horizontal, 14)

            // Activity breakdown
            VStack(spacing: 2) {
                ForEach(store.todayStats) { stat in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(stat.isWork ? Color.green : Color.blue)
                            .frame(width: 6, height: 6)
                        Text(stat.activity.displayName)
                            .font(.caption)
                        Spacer()
                        Text("\(String(format: "%.0f", stat.percentage))%")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text("\(stat.count)m")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                            .frame(width: 28, alignment: .trailing)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 3)
                }
            }

        }
        .padding(.vertical, 8)
    }

    private func objectivesSection(_ objectives: DayObjectives) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "target")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                Text("Today's Objectives")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.top, 1)
                Text(objectives.mainObjective)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(3)
            }

            let secondary = objectives.secondaryObjectives.filter { !$0.isEmpty }
            if !secondary.isEmpty {
                ForEach(secondary, id: \.self) { objective in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 4))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        Text(objective)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            MenubarActionButton(
                icon: store.trackingState.isActive ? "pause.fill" : "play.fill",
                label: store.trackingState.isActive ? "Stop Tracking" : "Resume Tracking",
                action: { store.send(.toggleTracking) }
            )
            .disabled(!store.trackingState.canToggle)

            MenubarActionButton(
                icon: "arrow.clockwise",
                label: "Refresh",
                action: { store.send(.refreshData) }
            )

            MenubarActionButton(
                icon: "chart.bar",
                label: "View Details",
                action: { store.send(.showDetails) }
            )

            MenubarActionButton(
                icon: "target",
                label: "Set Day Objectives",
                action: { store.send(.showObjectives) }
            )

        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var debugSection: some View {
        #if DEBUG
        Divider()
            .padding(.horizontal, 12)

        VStack(alignment: .leading, spacing: 4) {
            Text("Debug")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .padding(.horizontal, 14)

            MenubarActionButton(
                icon: "bolt.fill",
                label: store.isForceTracking ? "Tracking..." : "Force Track",
                action: { store.send(.forceTrack) }
            )
            .disabled(store.isForceTracking)

            MenubarActionButton(
                icon: "trash",
                label: store.isClearingTodayData ? "Clearing..." : "Clear Today's Data",
                action: { store.send(.clearTodayData) }
            )
            .disabled(store.isClearingTodayData)

            MenubarActionButton(
                icon: "tray.and.arrow.down.fill",
                label: "Force Track & Sample",
                action: {
                    store.send(.forceTrackAndSample)
                    dismissPopover()
                }
            )
            .disabled(store.isSampling)

            MenubarActionButton(
                icon: "timer",
                label: "Force Track & Sample with Delay",
                action: { store.send(.forceTrackAndSampleWithDelay) }
            )
            .disabled(store.isSampling)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .sheet(isPresented: Binding(
            get: { store.showDelayInput },
            set: { _ in }
        )) {
            SampleDelaySheet { seconds in
                store.send(.sampleWithDelayConfirmed(seconds: seconds))
                dismissPopover()
            }
        }
        #endif
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: Binding(
                get: { store.launchAtLogin },
                set: { _ in store.send(.toggleLaunchAtLogin) }
            )) {
                HStack(spacing: 8) {
                    Image(systemName: "gear")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text("Launch at Login")
                }
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)

            MenubarActionButton(
                icon: "gearshape",
                label: "Settings",
                action: { store.send(.showSettings) }
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Popover Dismiss

    /// Dismiss the menubar popover by finding the enclosing NSPopover.
    private func dismissPopover() {
        DispatchQueue.main.async {
            NSApp.keyWindow?.performClose(nil)
        }
    }

    // MARK: - Helpers

    private var iconColor: Color {
        switch store.trackingState {
        case .active:
            return .green
        case .pausedManual:
            return .orange
        case .beforeWorkHours, .afterWorkHours:
            return .purple
        }
    }
}

// MARK: - Menubar Action Button

/// A button with hover effect for the menubar popover.
private struct MenubarActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(label)
                    .font(.body)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Sample Delay Sheet

#if DEBUG
private struct SampleDelaySheet: View {
    let onConfirm: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var delayText: String

    init(onConfirm: @escaping (Int) -> Void) {
        self.onConfirm = onConfirm
        let saved = UserDefaults.standard.integer(forKey: "lastSampleDelay")
        _delayText = State(initialValue: String(saved > 0 ? saved : 5))
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Sample Delay")
                .font(.headline)
            Text("Enter delay in seconds before sampling")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Seconds", text: $delayText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Sample") {
                    let seconds = Int(delayText) ?? 5
                    onConfirm(seconds)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }
}
#endif
