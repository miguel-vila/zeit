import ComposableArchitecture
import SwiftUI

/// The menubar popover: the day's figures and the menu's controls, plus the
/// panels they open.
struct MenubarView: View {
    @Bindable var store: StoreOf<MenubarFeature>

    /// Height the popover may take on the screen that shows it. The app
    /// delegate knows which screen that is; the view only spends the budget.
    var availableHeight: CGFloat

    var body: some View {
        MenubarContentView(store: store, availableHeight: availableHeight)
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
}

/// The menu's rows on their own, with nothing presented. The app delegate lays
/// a copy of this out to find the height the popover needs, which is why it
/// carries no panels: laying it out must show nothing and change nothing.
struct MenubarContentView: View {
    let store: StoreOf<MenubarFeature>
    let availableHeight: CGFloat

    /// Height of the rows that never scroll, measured at runtime so the summary
    /// can claim the rest of the screen and no more.
    @State private var pinnedHeight: CGFloat = 0

    /// Natural height of the summary. The menu takes this height while it fits
    /// on screen, so the whole day is in view without scrolling.
    @State private var summaryHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                headerSection

                Divider()
                    .padding(.horizontal, 12)
            }
            .measuringPinnedHeight()

            summarySection

            controlsSection
                .measuringPinnedHeight()
        }
        .frame(width: MenubarContentView.width)
        .onPreferenceChange(PinnedHeightKey.self) { pinnedHeight = $0 }
    }

    /// The menu's width, fixed so that a layout done for measurement matches
    /// the one the popover shows.
    static let width: CGFloat = 300

    // MARK: - Sections

    /// The day's reading. It grows with the number of activity types, so it
    /// takes its natural height until that would push the controls past the
    /// bottom of the screen, and scrolls from there.
    ///
    /// The height is explicit because a scroll view has no height of its own:
    /// left to size itself, it gives the hosting controller nothing to report
    /// and the popover falls back to its default size.
    private var summarySection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let objectives = store.dayObjectives {
                    objectivesSection(objectives)
                    Divider()
                        .padding(.horizontal, 12)
                }

                if store.totalActivities > 0 {
                    statsSection
                    Divider()
                        .padding(.horizontal, 12)
                }
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: SummaryHeightKey.self, value: proxy.size.height)
                }
            )
        }
        .frame(height: min(summaryHeight, summaryMaxHeight))
        .onPreferenceChange(SummaryHeightKey.self) { summaryHeight = $0 }
    }

    /// What is left for the summary once the pinned rows have their space. The
    /// floor keeps a few rows readable when the pinned rows take almost all of
    /// the budget.
    private var summaryMaxHeight: CGFloat {
        max(Self.minimumSummaryHeight, availableHeight - pinnedHeight)
    }

    private static let minimumSummaryHeight: CGFloat = 160

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            actionsSection

            // Debug (debug builds only)
            debugSection

            Divider()
                .padding(.horizontal, 12)

            settingsSection

            Divider()
                .padding(.horizontal, 12)

            MenubarActionButton(
                icon: "power",
                label: "Quit Zeit",
                action: { store.send(.quitApp) }
            )
            .keyboardShortcut("q")
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

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
            // The primary group's share — the same number the icon shows — with
            // the group's label, which the icon has no room for.
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(store.primaryGroup.shortName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(store.primaryGroupPercentage))%")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.quaternary)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(store.primaryGroup.color.opacity(0.8))
                            .frame(
                                width: max(
                                    0,
                                    geometry.size.width * store.primaryGroupPercentage / 100
                                )
                            )
                    }
                }
                .frame(height: 5)
            }
            .padding(.horizontal, 14)

            // Every group, primary or not, so the day can be read against the
            // groups it was not judged by. Unclassified joins them once a type
            // has gone missing.
            VStack(spacing: 2) {
                ForEach(ActivityGroup.allCases, id: \.self) { group in
                    groupShareRow(
                        title: group.displayName,
                        color: group.color,
                        percentage: store.state.percentage(of: group),
                        isPrimary: group == store.primaryGroup
                    )
                }

                if store.unclassifiedPercentage > 0 {
                    groupShareRow(
                        title: ActivityGroup.unclassifiedLabel,
                        color: ActivityGroup.unclassifiedColor,
                        percentage: store.unclassifiedPercentage,
                        isPrimary: false
                    )
                }
            }

            Divider()
                .padding(.horizontal, 14)

            // Activity breakdown
            VStack(spacing: 2) {
                ForEach(store.todayStats) { stat in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(stat.group.sectionColor)
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

    /// One group's share of the day. The primary group is set in bold, so the
    /// icon's number can be found in the list.
    private func groupShareRow(
        title: String,
        color: Color,
        percentage: Double,
        isPrimary: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isPrimary ? "largecircle.fill.circle" : "circle.fill")
                .font(.system(size: isPrimary ? 8 : 6))
                .foregroundStyle(color)
                .frame(width: 8)
            Text(title)
                .font(.caption)
                .fontWeight(isPrimary ? .semibold : .regular)
            Spacer()
            Text("\(String(format: "%.0f", percentage))%")
                .font(.caption)
                .fontWeight(isPrimary ? .semibold : .regular)
                .monospacedDigit()
                .foregroundStyle(isPrimary ? .primary : .secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
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

            MenubarActionButton(
                icon: "trash",
                label: store.isClearingTodayData ? "Clearing..." : "Clear Today's Data",
                action: { store.send(.clearTodayData) }
            )
            .disabled(store.isClearingTodayData)
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
        case .outsideSchedule:
            return .purple
        }
    }
}

// MARK: - Height Measurement

private struct SummaryHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct PinnedHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value += nextValue()
    }
}

extension View {
    /// Report this view's height as part of the menubar's pinned rows.
    fileprivate func measuringPinnedHeight() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: PinnedHeightKey.self, value: proxy.size.height)
            }
        )
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
