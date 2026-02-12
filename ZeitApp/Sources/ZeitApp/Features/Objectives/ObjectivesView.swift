import ComposableArchitecture
import SwiftUI

struct ObjectivesView: View {
    @Bindable var store: StoreOf<ObjectivesFeature>

    private var canSave: Bool {
        !store.mainObjective.trimmingCharacters(in: .whitespaces).isEmpty && !store.isSaving
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Day Objectives")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(store.date)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "target")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if store.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Main objective
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text("Main Objective")
                            .fontWeight(.semibold)
                    } icon: {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    TextField(
                        "e.g., Complete the API integration for project X",
                        text: $store.mainObjective
                    )
                    .textFieldStyle(.roundedBorder)
                }

                // Secondary objectives
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text("Secondary Objectives")
                            .fontWeight(.semibold)
                    } icon: {
                        Image(systemName: "list.bullet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("Optional goals for the day")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

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

                Button {
                    store.send(.save)
                } label: {
                    HStack(spacing: 4) {
                        if store.isSaving {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 12, height: 12)
                        }
                        Text("Save")
                    }
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(22)
        .frame(minWidth: 460, minHeight: 280)
        .task {
            await store.send(.task).finish()
        }
    }
}
