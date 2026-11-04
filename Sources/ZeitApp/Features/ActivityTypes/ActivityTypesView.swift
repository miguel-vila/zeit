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
                        // One section per group, in the order the enum declares
                        ForEach(ActivityGroup.allCases, id: \.self) { group in
                            activitySection(for: group)
                        }
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

    /// A group's section: every group is shown, empty or not, so a type can be
    /// added to a group the machine does not use yet.
    private func activitySection(for group: ActivityGroup) -> some View {
        let types = store.state.types(in: group)
        let color = group.color
        let onAdd = { store.send(.addType(group: group)) }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: group.iconName)
                    .foregroundStyle(color)
                    .font(.subheadline)
                Text(group.displayName)
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
                            onUpdate: { name, desc in
                                store.send(
                                    .updateType(id: type.id, name: name, description: desc)
                                )
                            },
                            onDelete: { store.send(.deleteType(id: type.id)) }
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
