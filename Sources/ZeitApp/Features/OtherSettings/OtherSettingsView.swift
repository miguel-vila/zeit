import ComposableArchitecture
import SwiftUI

struct OtherSettingsView: View {
    @Bindable var store: StoreOf<OtherSettingsFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Configure your work schedule and other options.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // MARK: - Work Hours

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
                                get: { store.startHour },
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
                                get: { store.startMinute },
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
                                get: { store.endHour },
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
                                get: { store.endMinute },
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
                            let isSelected = store.workDays.contains(day)
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

                    // MARK: - Debug Mode

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
                }
            }

            // Buttons
            HStack {
                Spacer()

                Button("Done") {
                    store.send(.done)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(minWidth: 500, minHeight: 420)
        .task {
            await store.send(.task).finish()
        }
    }

    // MARK: - Helpers

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
}
