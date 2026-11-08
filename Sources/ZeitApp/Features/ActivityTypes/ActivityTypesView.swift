import ComposableArchitecture
import SwiftUI

struct ActivityTypesView: View {
    @Bindable var store: StoreOf<ActivityTypesFeature>

    /// Onboarding asks the primary group as a question with two answers and owns
    /// the Continue button; settings offers all three groups in a picker and has
    /// its own save flow. The mode lives in state because the reducer needs it
    /// too: in onboarding the answer re-seeds the selection.
    private var mode: ActivityTypesFeature.Mode { store.mode }

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

            primaryGroupSection

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
                        ForEach(visibleGroups, id: \.self) { group in
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
                    if store.acceptsEdits {
                        Button("Reset to suggested set") {
                            store.send(.resetToSuggestedSet)
                        }

                        Button("Clear All") {
                            store.send(.clearAll)
                        }
                    }

                    Spacer()

                    selectionCounter

                    primaryButton
                }
            }
        }
        .padding(22)
        .frame(minWidth: 500, minHeight: 480)
        .alert($store.scope(state: \.alert, action: \.alert))
        .task {
            await store.send(.task).finish()
        }
    }

    // MARK: - Primary Button

    /// One button for the state the editor is in: Edit opens the rows, Save
    /// writes them and closes them again, which is how the user sees that the
    /// write happened. Onboarding only ever saves.
    private var primaryButton: some View {
        let title: String
        let action: ActivityTypesFeature.Action

        if store.acceptsEdits {
            title = mode == .onboarding ? "Continue" : "Save"
            action = .done
        } else {
            title = "Edit"
            action = .edit
        }

        return Button(title) {
            store.send(action)
        }
        .buttonStyle(.borderedProminent)
        // Only a save can be invalid; asking to edit never is.
        .disabled(store.acceptsEdits && !store.isValid)
    }

    // MARK: - Selection Counter

    /// The size of the selection against the cap, with the band that classifies
    /// best: every selected type costs prompt tokens and, past a point, accuracy.
    private var selectionCounter: some View {
        let count = store.types.count
        let range = ActivityCatalog.comfortableRange
        let overCap = count > ActivityTypeValidator.maxTotalTypes

        return VStack(alignment: .trailing, spacing: 1) {
            Text("\(count) of \(ActivityTypeValidator.maxTotalTypes) selected")
                .font(.caption)
                .foregroundStyle(overCap ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            Text("\(range.lowerBound) to \(range.upperBound) types classify best")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Primary Group

    /// The group the day is judged by: the number the menubar icon shows.
    @ViewBuilder
    private var primaryGroupSection: some View {
        switch mode {
        case .onboarding:
            VStack(alignment: .leading, spacing: 8) {
                Text("What do you want to spend your time on?")
                    .font(.headline)

                HStack(spacing: 10) {
                    // Only the two groups that can be a goal; `personal` is the
                    // residual group, measured against and never for.
                    ForEach(ActivityGroup.goals, id: \.self) { group in
                        goalButton(group)
                    }
                }
            }
        case .settings:
            HStack(spacing: 8) {
                Text("Measure my day by")
                    .font(.subheadline)

                // Settings offers all three: a machine may legitimately be
                // judged by its personal time.
                Picker("", selection: Binding(
                    get: { store.primaryGroup },
                    set: { store.send(.setPrimaryGroup($0)) }
                )) {
                    ForEach(ActivityGroup.allCases, id: \.self) { group in
                        Text(group.displayName).tag(group)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .disabled(!store.acceptsEdits)
            }
        }
    }

    private func goalButton(_ group: ActivityGroup) -> some View {
        let isSelected = store.primaryGroup == group

        return Button {
            store.send(.setPrimaryGroup(group))
        } label: {
            HStack(spacing: 8) {
                Image(systemName: group.iconName)
                    .foregroundStyle(isSelected ? group.color : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.goalLabel)
                        .fontWeight(.medium)
                    Text(group.goalDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? group.color.opacity(0.12) : Color.primary.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? group.color : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Activity Section

    /// While editing, every group gets a section, empty or not, so a type can be
    /// added to a group the machine does not use yet. Read-only, an empty group
    /// has nothing to show.
    private var visibleGroups: [ActivityGroup] {
        ActivityGroup.allCases(primaryFirst: store.primaryGroup)
            .filter { store.acceptsEdits || !store.state.types(in: $0).isEmpty }
    }

    private func activitySection(for group: ActivityGroup) -> some View {
        let types = store.state.types(in: group)
        let color = group.color
        let onAdd: () -> Void = { store.send(.addType(group: group)) }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: group.iconName)
                    .foregroundStyle(color)
                    .font(.subheadline)
                Text(group.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                if group == store.primaryGroup {
                    Text("primary")
                        .font(.caption2)
                        .foregroundStyle(color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(color.opacity(0.12), in: Capsule())
                }

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
                            isEditable: store.acceptsEdits,
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

            if store.acceptsEdits {
                suggestionChips(for: group)

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

    // MARK: - Suggestion Chips

    /// What Zeit offers for this group and the user has not taken. One click adds
    /// the type with its description, and the chip goes away because the
    /// suggestion is now in the selection.
    @ViewBuilder
    private func suggestionChips(for group: ActivityGroup) -> some View {
        let unselected = store.state.unselectedSuggestions(in: group)

        if !unselected.isEmpty {
            FlowLayout(spacing: 4) {
                ForEach(unselected) { suggestion in
                    Button {
                        store.send(.addSuggestion(id: suggestion.id))
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "plus")
                                .font(.caption2)
                            Text(suggestion.name)
                                .font(.caption)
                        }
                        .foregroundStyle(group.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(group.color.opacity(0.08), in: Capsule())
                        .overlay(
                            Capsule().stroke(group.color.opacity(0.25), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(suggestion.description)
                }
            }
            .padding(.horizontal, 8)
        }
    }
}

// MARK: - Flow Layout

/// Wraps its subviews onto as many rows as they need. Chips are short and there
/// are up to ten of them per group, so a single `HStack` would clip.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = layout(subviews: subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        for row in layout(subviews: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func layout(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width

            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
                current.indices = [index]
                current.width = size.width
                current.height = size.height
            } else {
                current.indices.append(index)
                current.width = needed
                current.height = max(current.height, size.height)
            }
        }

        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

// MARK: - Activity Type Row

private struct ActivityTypeRow: View {
    let type: ActivityType
    let color: Color
    let isEditable: Bool
    let onUpdate: (String?, String?) -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var editingName: String
    @State private var editingDescription: String

    init(
        type: ActivityType,
        color: Color,
        isEditable: Bool,
        onUpdate: @escaping (String?, String?) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.type = type
        self.color = color
        self.isEditable = isEditable
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
                HStack(spacing: 6) {
                    if isEditable {
                        TextField("Name", text: $editingName)
                            .font(.body)
                            .fontWeight(.medium)
                            .textFieldStyle(.plain)
                            .onChange(of: editingName) { _, newValue in
                                onUpdate(newValue, nil)
                            }
                    } else {
                        Text(type.name)
                            .font(.body)
                            .fontWeight(.medium)
                    }

                    // A twin is only separable by what the description says, so
                    // the row says so rather than letting the pair look fine.
                    if ActivityCatalog.isTwin(type) {
                        Text("twin")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                            .help(ActivityCatalog.twinHint)
                    }
                }

                if isEditable {
                    TextField("Description (used as context for AI classification)", text: $editingDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textFieldStyle(.plain)
                        .onChange(of: editingDescription) { _, newValue in
                            onUpdate(nil, newValue)
                        }
                } else {
                    Text(type.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if ActivityCatalog.needsTwinDetail(type) {
                    Text(ActivityCatalog.twinHint)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                if let error = fieldError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            if isEditable, isHovered {
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
                .fill(
                    isEditable && isHovered
                        ? Color.primary.opacity(0.04)
                        : Color.primary.opacity(0.015)
                )
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
