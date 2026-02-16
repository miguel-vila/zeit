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
        .frame(minWidth: 600, minHeight: 400)
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
        case .workHours:
            settingsWorkHoursTab
        case .debug:
            settingsDebugTab
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
        VStack(alignment: .leading, spacing: 16) {
            Text("AI Models")
                .font(.title2)
                .fontWeight(.bold)

            Text("Models used for activity classification. Models run locally on your Mac.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            VStack(spacing: 8) {
                ForEach(store.models.models) { model in
                    SettingsModelRow(model: model)
                }
            }

            Spacer()
        }
        .padding(22)
    }

    // MARK: - Work Hours Tab

    private var settingsWorkHoursTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Work Hours")
                .font(.title2)
                .fontWeight(.bold)

            Text("Set your typical work schedule. Tracking only runs during these hours on the selected days.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            VStack(spacing: 12) {
                // Start time picker
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 36, height: 36)

                        Image(systemName: "sunrise.fill")
                            .foregroundStyle(.blue)
                            .font(.body)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start Time")
                            .fontWeight(.semibold)

                        Text("When your work day begins")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Picker("", selection: Binding(
                            get: { store.workHours.startHour },
                            set: { store.send(.setStartHour($0)) }
                        )) {
                            ForEach(0..<24) { hour in
                                Text(formatHour(hour)).tag(hour)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 70)

                        Text(":")
                            .fontWeight(.medium)

                        Picker("", selection: Binding(
                            get: { store.workHours.startMinute },
                            set: { store.send(.setStartMinute($0)) }
                        )) {
                            ForEach(minuteOptions, id: \.self) { minute in
                                Text(String(format: "%02d", minute)).tag(minute)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 55)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.015))
                )

                // End time picker
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange.opacity(0.1))
                            .frame(width: 36, height: 36)

                        Image(systemName: "sunset.fill")
                            .foregroundStyle(.orange)
                            .font(.body)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("End Time")
                            .fontWeight(.semibold)

                        Text("When your work day ends")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Picker("", selection: Binding(
                            get: { store.workHours.endHour },
                            set: { store.send(.setEndHour($0)) }
                        )) {
                            ForEach(0..<24) { hour in
                                Text(formatHour(hour)).tag(hour)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 70)

                        Text(":")
                            .fontWeight(.medium)

                        Picker("", selection: Binding(
                            get: { store.workHours.endMinute },
                            set: { store.send(.setEndMinute($0)) }
                        )) {
                            ForEach(minuteOptions, id: \.self) { minute in
                                Text(String(format: "%02d", minute)).tag(minute)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 55)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.015))
                )

                // Work days selector
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.green.opacity(0.1))
                            .frame(width: 36, height: 36)

                        Image(systemName: "calendar")
                            .foregroundStyle(.green)
                            .font(.body)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Work Days")
                            .fontWeight(.semibold)

                        Text("Days when tracking is active")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 4)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 8)
                        .fill(Color.primary.opacity(0.015))
                )

                HStack(spacing: 6) {
                    ForEach(ZeitConfig.Weekday.allCases, id: \.rawValue) { day in
                        let isSelected = store.workHours.workDays.contains(day)
                        Button {
                            store.send(.toggleWorkDay(day))
                        } label: {
                            Text(day.shortName)
                                .font(.caption)
                                .fontWeight(isSelected ? .semibold : .regular)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
                                )
                                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 8, bottomTrailingRadius: 8, topTrailingRadius: 0)
                        .fill(Color.primary.opacity(0.015))
                )
            }

            if let error = store.workHours.saveError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Save") {
                    store.send(.saveWorkHours)
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding(22)
    }

    private var minuteOptions: [Int] {
        stride(from: 0, to: 60, by: 5).map { $0 }
    }

    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: date)
    }

    // MARK: - Debug Tab

    private var settingsDebugTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Debug")
                .font(.title2)
                .fontWeight(.bold)

            Text("Developer and debugging options.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            store.debugModeEnabled
                                ? Color.orange.opacity(0.1)
                                : Color.primary.opacity(0.05)
                        )
                        .frame(width: 36, height: 36)

                    Image(systemName: "ladybug.fill")
                        .foregroundStyle(store.debugModeEnabled ? .orange : .secondary)
                        .font(.body)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Debug Mode")
                        .fontWeight(.semibold)

                    Text("Shows a debug section with Force Track in the menubar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { store.debugModeEnabled },
                    set: { _ in store.send(.toggleDebugMode) }
                ))
                .labelsHidden()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.015))
            )

            Spacer()
        }
        .padding(22)
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

// MARK: - Model Row (read-only)

private struct SettingsModelRow: View {
    let model: SettingsFeature.SettingsModelsState.ModelInfo

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(model.isDownloaded ? Color.green.opacity(0.1) : Color.secondary.opacity(0.1))
                    .frame(width: 36, height: 36)

                Image(systemName: model.isDownloaded ? "checkmark.circle.fill" : (model.isVision ? "eye.fill" : "text.bubble.fill"))
                    .foregroundStyle(model.isDownloaded ? .green : .secondary)
                    .font(.body)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .fontWeight(.semibold)

                Text("\(model.isVision ? "Vision" : "Text") model (~\(String(format: "%.1f", model.approximateSizeGB)) GB)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.isDownloaded {
                Text("Downloaded")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.green)
            } else {
                Text("Not Downloaded")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.orange)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.015))
        )
    }
}
