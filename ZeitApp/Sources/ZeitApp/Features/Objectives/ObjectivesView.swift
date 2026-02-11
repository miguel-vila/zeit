import ComposableArchitecture
import SwiftUI

struct ObjectivesView: View {
    @Bindable var store: StoreOf<ObjectivesFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Set Your Day Objectives")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Date: \(store.date)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if store.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Main objective
                VStack(alignment: .leading, spacing: 4) {
                    Text("Main Objective:")
                        .fontWeight(.semibold)

                    TextField(
                        "e.g., Complete the API integration for project X",
                        text: $store.mainObjective
                    )
                    .textFieldStyle(.roundedBorder)
                }

                // Secondary objectives
                VStack(alignment: .leading, spacing: 4) {
                    Text("Secondary Objectives (optional):")
                        .fontWeight(.semibold)

                    TextField(
                        "e.g., Review pull requests",
                        text: $store.secondary1
                    )
                    .textFieldStyle(.roundedBorder)

                    TextField(
                        "e.g., Write documentation",
                        text: $store.secondary2
                    )
                    .textFieldStyle(.roundedBorder)
                }

                Spacer()
            }

            // Buttons
            HStack {
                Button("Cancel") {
                    store.send(.cancel)
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Save") {
                    store.send(.save)
                }
                .keyboardShortcut(.return)
                .disabled(
                    store.mainObjective.trimmingCharacters(in: .whitespaces).isEmpty
                        || store.isSaving
                )
            }
        }
        .padding(20)
        .frame(minWidth: 450, minHeight: 250)
        .task {
            await store.send(.task).finish()
        }
    }
}
