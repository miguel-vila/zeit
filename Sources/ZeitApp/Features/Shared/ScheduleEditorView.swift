import SwiftUI

/// The schedule editor used by both onboarding and settings: Always or Windows,
/// and under Windows a list of window rows with add and remove.
struct ScheduleEditorView: View {
    let state: ScheduleEditorState

    let onSetAlways: (Bool) -> Void
    let onAddWindow: () -> Void
    let onRemoveWindow: (UUID) -> Void
    let onChangeWindow: (ScheduleWindowDraft) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: Binding(
                get: { state.isAlways },
                set: { onSetAlways($0) }
            )) {
                Text("Windows").tag(false)
                Text("Always").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if state.isAlways {
                HStack(spacing: 12) {
                    ScheduleSettingsIcon(name: "infinity", color: .accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Always Tracking")
                            .fontWeight(.semibold)

                        Text("Every day, around the clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.015))
                )
            } else {
                // One window needs no header and no remove control, so the
                // common case reads as a time picker rather than an editor.
                let showsRowChrome = state.windows.count > 1

                ForEach(Array(state.windows.enumerated()), id: \.element.id) { index, window in
                    VStack(alignment: .leading, spacing: 12) {
                        if showsRowChrome {
                            HStack {
                                Text("Window \(index + 1)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Button {
                                    onRemoveWindow(window.id)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .help("Remove this window")
                            }
                        }

                        ScheduleWindowPickerView(
                            window: window,
                            onChange: onChangeWindow
                        )
                    }
                }

                HStack {
                    Button {
                        onAddWindow()
                    } label: {
                        Label("Add Window", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .font(.caption)

                    Spacer()
                }
            }
        }
    }
}

/// One window: start time, end time and the days it starts on.
struct ScheduleWindowPickerView: View {
    let window: ScheduleWindowDraft
    let onChange: (ScheduleWindowDraft) -> Void

    var body: some View {
        // Start time picker
        HStack(spacing: 12) {
            ScheduleSettingsIcon(name: "sunrise.fill", color: .blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Start Time")
                    .fontWeight(.semibold)

                Text("When tracking starts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            timePickerControls(
                hour: window.startHour,
                minute: window.startMinute,
                onSetHour: { hour in change { $0.startHour = hour } },
                onSetMinute: { minute in change { $0.startMinute = minute } }
            )
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.015))
        )

        // End time picker
        HStack(spacing: 12) {
            ScheduleSettingsIcon(name: "sunset.fill", color: .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("End Time")
                    .fontWeight(.semibold)

                Text(window.window.isOvernight ? "Next day — this window runs overnight" : "When tracking stops")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            timePickerControls(
                hour: window.endHour,
                minute: window.endMinute,
                onSetHour: { hour in change { $0.endHour = hour } },
                onSetMinute: { minute in change { $0.endMinute = minute } }
            )
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.015))
        )

        // Days selector
        HStack(spacing: 12) {
            ScheduleSettingsIcon(name: "calendar", color: .green)

            VStack(alignment: .leading, spacing: 2) {
                Text("Days")
                    .fontWeight(.semibold)

                Text("Days this window starts on")
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
                let isSelected = window.days.contains(day)
                Button {
                    change { draft in
                        if draft.days.contains(day) {
                            draft.days.remove(day)
                        } else {
                            draft.days.insert(day)
                        }
                    }
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

    // MARK: - Subviews

    /// Send the row back edited, so the reducer only ever sees whole windows.
    private func change(_ edit: (inout ScheduleWindowDraft) -> Void) {
        var updated = window
        edit(&updated)
        onChange(updated)
    }

    private func timePickerControls(
        hour: Int,
        minute: Int,
        onSetHour: @escaping (Int) -> Void,
        onSetMinute: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 4) {
            Picker("", selection: Binding(
                get: { hour },
                set: { onSetHour($0) }
            )) {
                ForEach(0..<24) { h in
                    Text(Self.formatHour(h)).tag(h)
                }
            }
            .labelsHidden()
            .frame(width: 70)

            Text(":")
                .fontWeight(.medium)

            Picker("", selection: Binding(
                get: { minute },
                set: { onSetMinute($0) }
            )) {
                ForEach(Self.minuteOptions, id: \.self) { m in
                    Text(String(format: "%02d", m)).tag(m)
                }
            }
            .labelsHidden()
            .frame(width: 55)
        }
    }

    // MARK: - Helpers

    static let minuteOptions: [Int] = stride(from: 0, to: 60, by: 5).map { $0 }

    static func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: date)
    }
}

/// The rounded icon tile the schedule rows share with the other settings rows.
private struct ScheduleSettingsIcon: View {
    let name: String
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.1))
                .frame(width: 36, height: 36)

            Image(systemName: name)
                .foregroundStyle(color)
                .font(.body)
        }
    }
}
