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

                    WorkHoursPickerView(
                        startHour: store.startHour,
                        startMinute: store.startMinute,
                        endHour: store.endHour,
                        endMinute: store.endMinute,
                        workDays: store.workDays,
                        onSetStartHour: { store.send(.setStartHour($0)) },
                        onSetStartMinute: { store.send(.setStartMinute($0)) },
                        onSetEndHour: { store.send(.setEndHour($0)) },
                        onSetEndMinute: { store.send(.setEndMinute($0)) },
                        onToggleWorkDay: { store.send(.toggleWorkDay($0)) }
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

}
