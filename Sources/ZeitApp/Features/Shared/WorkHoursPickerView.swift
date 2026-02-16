import SwiftUI

/// Reusable work hours and work days picker used in both onboarding and settings.
struct WorkHoursPickerView: View {
    let startHour: Int
    let startMinute: Int
    let endHour: Int
    let endMinute: Int
    let workDays: Set<ZeitConfig.Weekday>

    let onSetStartHour: (Int) -> Void
    let onSetStartMinute: (Int) -> Void
    let onSetEndHour: (Int) -> Void
    let onSetEndMinute: (Int) -> Void
    let onToggleWorkDay: (ZeitConfig.Weekday) -> Void

    var body: some View {
        // Start time picker
        HStack(spacing: 12) {
            settingsIcon("sunrise.fill", color: .blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Start Time")
                    .fontWeight(.semibold)

                Text("When your work day begins")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            timePickerControls(
                hour: startHour,
                minute: startMinute,
                onSetHour: onSetStartHour,
                onSetMinute: onSetStartMinute
            )
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.015))
        )

        // End time picker
        HStack(spacing: 12) {
            settingsIcon("sunset.fill", color: .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("End Time")
                    .fontWeight(.semibold)

                Text("When your work day ends")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            timePickerControls(
                hour: endHour,
                minute: endMinute,
                onSetHour: onSetEndHour,
                onSetMinute: onSetEndMinute
            )
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.015))
        )

        // Work days selector
        HStack(spacing: 12) {
            settingsIcon("calendar", color: .green)

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
                let isSelected = workDays.contains(day)
                Button {
                    onToggleWorkDay(day)
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

    private func settingsIcon(_ name: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.1))
                .frame(width: 36, height: 36)

            Image(systemName: name)
                .foregroundStyle(color)
                .font(.body)
        }
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
