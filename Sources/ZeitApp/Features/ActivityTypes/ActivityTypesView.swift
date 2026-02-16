import ComposableArchitecture
import SwiftUI

struct ActivityTypesView: View {
    @Bindable var store: StoreOf<ActivityTypesFeature>

    /// Whether to show the Done button (used in onboarding; settings has its own save flow)
    var showDoneButton: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Activity Types")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Configure the activity categories that Zeit uses to classify your screen time.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if store.isLoading {
                Spacer()
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Work activities section
                        activitySection(
                            title: "Work Activities",
                            icon: "briefcase.fill",
                            color: Color(red: 0.2, green: 0.7, blue: 0.6),
                            types: store.workTypes,
                            onAdd: { store.send(.addWorkType) },
                            onUpdate: { id, name, desc in
                                store.send(.updateWorkType(id: id, name: name, description: desc))
                            },
                            onDelete: { id in store.send(.deleteWorkType(id: id)) }
                        )

                        // Personal activities section
                        activitySection(
                            title: "Personal Activities",
                            icon: "house.fill",
                            color: Color(red: 0.6, green: 0.4, blue: 0.8),
                            types: store.personalTypes,
                            onAdd: { store.send(.addPersonalType) },
                            onUpdate: { id, name, desc in
                                store.send(.updatePersonalType(id: id, name: name, description: desc))
                            },
                            onDelete: { id in store.send(.deletePersonalType(id: id)) }
                        )
                    }
                }

                // Error message
                if let error = store.saveError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                // Action buttons
                HStack(spacing: 12) {
                    Button("Reset to Defaults") {
                        store.send(.resetToDefaults)
                    }

                    Button("Clear All") {
                        store.send(.clearAll)
                    }

                    Spacer()

                    if showDoneButton {
                        Button("Continue") {
                            store.send(.done)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!store.isValid)
                    }
                }
            }
        }
        .padding(22)
        .frame(minWidth: 500, minHeight: 480)
        .task {
            await store.send(.task).finish()
        }
    }

    // MARK: - Activity Section

    private func activitySection(
        title: String,
        icon: String,
        color: Color,
        types: [ActivityType],
        onAdd: @escaping () -> Void,
        onUpdate: @escaping (String, String?, String?) -> Void,
        onDelete: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.subheadline)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Text("\(types.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            if types.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Text("No activity types")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Add one") { onAdd() }
                            .font(.caption)
                    }
                    .padding(.vertical, 12)
                    Spacer()
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.02))
                )
            } else {
                VStack(spacing: 4) {
                    ForEach(types) { type in
                        ActivityTypeRow(
                            type: type,
                            color: color,
                            onUpdate: { name, desc in onUpdate(type.id, name, desc) },
                            onDelete: { onDelete(type.id) }
                        )
                    }
                }
            }

            Button {
                onAdd()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.caption)
                    Text("Add")
                        .font(.caption)
                }
                .foregroundStyle(color)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Activity Type Row

private struct ActivityTypeRow: View {
    let type: ActivityType
    let color: Color
    let onUpdate: (String?, String?) -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var editingName: String
    @State private var editingDescription: String

    init(
        type: ActivityType,
        color: Color,
        onUpdate: @escaping (String?, String?) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.type = type
        self.color = color
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        _editingName = State(initialValue: type.name)
        _editingDescription = State(initialValue: type.description)
    }

    private var fieldError: String? {
        ActivityTypeValidator.validateField(type)?.localizedDescription
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(color.opacity(0.6))
                .frame(width: 6, height: 6)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 4) {
                TextField("Name", text: $editingName)
                    .font(.body)
                    .fontWeight(.medium)
                    .textFieldStyle(.plain)
                    .onChange(of: editingName) { _, newValue in
                        onUpdate(newValue, nil)
                    }

                TextField("Description (used as context for AI classification)", text: $editingDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textFieldStyle(.plain)
                    .onChange(of: editingDescription) { _, newValue in
                        onUpdate(nil, newValue)
                    }

                if let error = fieldError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            if isHovered {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.body)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.04) : Color.primary.opacity(0.015))
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
