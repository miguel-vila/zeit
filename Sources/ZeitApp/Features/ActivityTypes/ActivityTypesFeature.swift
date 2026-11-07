import ComposableArchitecture
import Foundation

/// Feature for editing activity types (used in both onboarding and settings).
///
/// Types are held in one flat list and sectioned by their group when rendered, so
/// the editor gains a section the moment `ActivityGroup` gains a case. The list
/// holds only what the user accepted or wrote; everything Zeit *offers* lives in
/// `ActivityCatalog` and reaches the list through a chip or a reset.
@Reducer
struct ActivityTypesFeature {
    /// Where this editor is shown.
    ///
    /// Onboarding treats the primary-group answer as a seed: picking one
    /// re-selects the suggested set for it, because there is nothing to lose yet.
    /// Settings must never do that — the selection there is the user's.
    enum Mode: Equatable, Sendable {
        case onboarding
        case settings
    }

    @ObservableState
    struct State: Equatable {
        var mode: Mode = .settings
        var types: [ActivityType] = []
        /// The group this machine is judged by, saved to the config on `done`.
        var primaryGroup: ActivityGroup = ZeitConfig.defaultClassification.primaryGroup
        var isLoading: Bool = true
        var saveError: String?

        /// Whether the suggested set may replace what is on screen.
        ///
        /// Onboarding seeds from the primary-group answer, which is right on a
        /// machine where nobody has chosen types and destructive on one where
        /// somebody has: `done` writes this list as the whole catalog, and
        /// onboarding opens whenever a permission is missing rather than only
        /// on a first run.
        ///
        /// It is a fact about the catalog that was loaded, not about which
        /// screen is open, so the load and a later goal change ask one
        /// question instead of each deciding for itself.
        var maySeedFromSuggestions: Bool {
            mode == .onboarding && !openedOnAChosenSelection
        }

        /// Whether the catalog this editor opened on was somebody's choice.
        /// Set when the types load; `false` until then, so a first run seeds.
        var openedOnAChosenSelection = false
        /// Asks before unselecting a type that today's entries still reference.
        @Presents var alert: AlertState<Action.Alert>?

        /// Whether the current configuration is valid for saving/continuing.
        ///
        /// Groups other than the primary one are not required to be populated: a
        /// machine has a group when it has types in that group.
        var isValid: Bool {
            !types.isEmpty
                && types.count <= ActivityTypeValidator.maxTotalTypes
                && types.contains { $0.group == primaryGroup }
                && types.allSatisfy({ ActivityTypeValidator.validateField($0) == nil })
        }

        /// The types belonging to `group`, in the order they were loaded or added.
        func types(in group: ActivityGroup) -> [ActivityType] {
            types.filter { $0.group == group }
        }

        /// The suggestions of `group` that are not in the selection, offered as
        /// chips under the group's rows.
        ///
        /// Matched by id, which is the id a suggestion gets when saved, so a
        /// chip does not come back for a type that is already selected.
        func unselectedSuggestions(in group: ActivityGroup) -> [ActivityCatalog.Suggestion] {
            let selected = Set(types.map(\.id))
            return ActivityCatalog.suggestions(in: group).filter { !selected.contains($0.id) }
        }
    }

    enum Action {
        case task
        case typesLoaded([ActivityType], primaryGroup: ActivityGroup)

        // Editing
        case setPrimaryGroup(ActivityGroup)
        case addType(group: ActivityGroup)
        case addSuggestion(id: String)
        case updateType(id: String, name: String?, description: String?)
        case deleteType(id: String)
        case todaysEntryCountLoaded(id: String, count: Int)
        case removeType(id: String)
        case alert(PresentationAction<Alert>)

        // Bulk
        case resetToSuggestedSet
        case clearAll

        // Save
        case done
        case saveCompleted(Result<Void, Error>)

        @CasePathable
        enum Alert: Equatable {
            case confirmRemove(id: String)
        }
    }

    @Dependency(\.databaseClient) var database
    @Dependency(\.classificationClient) var classification
    @Dependency(\.uuid) var uuid

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                state.isLoading = true
                return .run { send in
                    let types = try await database.getActivityTypes()
                    await send(.typesLoaded(types, primaryGroup: classification.primaryGroup()))
                }

            case .typesLoaded(let types, let primaryGroup):
                state.isLoading = false
                state.primaryGroup = primaryGroup
                // Onboarding opens on the suggested set for the answer, but
                // only over the starter set the database seeded itself with:
                // anything else is a selection somebody chose.
                state.openedOnAChosenSelection = !ActivityCatalog.isUnchosen(types)
                state.types = state.maySeedFromSuggestions
                    ? ActivityCatalog.suggestedSelection(for: primaryGroup)
                    : types
                return .none

            // MARK: - Editing

            case .setPrimaryGroup(let group):
                state.primaryGroup = group
                state.saveError = nil
                if state.maySeedFromSuggestions {
                    state.types = ActivityCatalog.suggestedSelection(for: group)
                }
                return .none

            case .addType(let group):
                state.types.append(
                    ActivityType(
                        id: "new_\(group.rawValue)_\(uuid().uuidString.prefix(8).lowercased())",
                        name: "",
                        description: "",
                        group: group
                    )
                )
                return .none

            case .addSuggestion(let id):
                guard
                    let suggestion = ActivityCatalog.suggestion(id: id),
                    !state.types.contains(where: { $0.id == id })
                else { return .none }
                state.types.append(suggestion.activityType)
                state.saveError = nil
                return .none

            case .updateType(let id, let name, let description):
                guard let index = state.types.firstIndex(where: { $0.id == id }) else {
                    return .none
                }
                if let name = name {
                    state.types[index].name = name
                }
                if let description = description {
                    state.types[index].description = description
                }
                state.saveError = nil
                return .none

            case .deleteType(let id):
                // Unselecting is reversible — re-adding regenerates the same id —
                // but it orphans today's entries into Unclassified in the
                // meantime, so the ones with history ask first.
                return .run { send in
                    let count = await todaysEntryCount(for: id)
                    await send(.todaysEntryCountLoaded(id: id, count: count))
                }

            case .todaysEntryCountLoaded(let id, let count):
                guard count > 0, let type = state.types.first(where: { $0.id == id }) else {
                    return .send(.removeType(id: id))
                }
                state.alert = .unselectWithEntries(type, count: count)
                return .none

            case .alert(.presented(.confirmRemove(let id))):
                return .send(.removeType(id: id))

            case .alert:
                return .none

            case .removeType(let id):
                state.types.removeAll { $0.id == id }
                return .none

            // MARK: - Bulk

            case .resetToSuggestedSet:
                state.types = ActivityCatalog.suggestedSelection(for: state.primaryGroup)
                state.saveError = nil
                return .none

            case .clearAll:
                state.types = []
                state.saveError = nil
                return .none

            // MARK: - Save

            case .done:
                // Regenerate IDs from names before saving
                for index in state.types.indices {
                    state.types[index].id = ActivityType.generateID(
                        from: state.types[index].name
                    )
                }

                let allTypes = state.types
                let primaryGroup = state.primaryGroup

                let errors = ActivityTypeValidator.validateAll(
                    allTypes, primaryGroup: primaryGroup
                )
                if let firstError = errors.first {
                    state.saveError = firstError.localizedDescription
                    return .none
                }

                return .run { send in
                    do {
                        try classification.savePrimaryGroup(primaryGroup)
                        try await database.saveActivityTypes(allTypes)
                        await send(.saveCompleted(.success(())))
                    } catch {
                        await send(.saveCompleted(.failure(error)))
                    }
                }

            case .saveCompleted(.success):
                state.saveError = nil
                return .none

            case .saveCompleted(.failure(let error)):
                state.saveError = error.localizedDescription
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }

    /// How many of today's entries carry `id`. A database that cannot be read
    /// reports zero: a failed count must not block the user from editing their
    /// own selection.
    private func todaysEntryCount(for id: String) async -> Int {
        let today = DayAttribution.current.today()

        guard let record = try? await database.getDayRecord(today) else { return 0 }
        return record.activities.filter { $0.activity.rawValue == id }.count
    }
}

// MARK: - Alerts

extension AlertState where Action == ActivityTypesFeature.Action.Alert {
    /// Names the count, because the cost of unselecting is proportional to it and
    /// invisible until the day is rendered.
    static func unselectWithEntries(_ type: ActivityType, count: Int) -> Self {
        Self {
            TextState("Remove “\(type.name)”?")
        } actions: {
            ButtonState(role: .destructive, action: .confirmRemove(id: type.id)) {
                TextState("Remove")
            }
            ButtonState(role: .cancel) {
                TextState("Keep")
            }
        } message: {
            TextState(
                """
                \(count) \(count == 1 ? "entry" : "entries") today \
                \(count == 1 ? "is" : "are") classified as “\(type.name)”. \
                \(count == 1 ? "It" : "They") will show as \
                \(ActivityGroup.unclassifiedLabel) instead.

                Adding it back later reconnects them.
                """
            )
        }
    }
}
