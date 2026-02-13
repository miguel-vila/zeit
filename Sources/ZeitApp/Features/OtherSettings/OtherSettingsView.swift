import ComposableArchitecture
import SwiftUI

struct OtherSettingsView: View {
    @Bindable var store: StoreOf<OtherSettingsFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with close button
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Other Settings")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Configure additional options for Zeit.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()

            // Debug mode toggle
            VStack(spacing: 8) {
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

                        Text("Shows additional controls like Force Track in the menubar")
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

            Spacer()

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
        .frame(minWidth: 500, minHeight: 300)
    }
}
