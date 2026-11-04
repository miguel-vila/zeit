import Testing

@testable import ZeitApp

/// The catalog is the picker's menu. It is never written to the database on its
/// own, and every entry has to survive the round trip the picker puts it
/// through: selected, saved, reloaded, matched against a chip again.
@Suite
struct ActivityCatalogTests {
    @Test
    func theCatalogIsWiderThanAnySelection() {
        #expect(ActivityCatalog.suggestions.count == 25)
        #expect(ActivityCatalog.suggestions.count < ActivityTypeValidator.maxTotalTypes)
    }

    @Test(arguments: ActivityGroup.allCases)
    func everyGroupHasSuggestions(group: ActivityGroup) {
        #expect(!ActivityCatalog.suggestions(in: group).isEmpty)
    }

    @Test
    func suggestionsInAGroupAreOnlyThatGroup() {
        for group in ActivityGroup.allCases {
            #expect(ActivityCatalog.suggestions(in: group).allSatisfy { $0.group == group })
        }
        let sectioned = ActivityGroup.allCases.flatMap { ActivityCatalog.suggestions(in: $0) }
        #expect(sectioned.count == ActivityCatalog.suggestions.count)
    }

    /// The property the whole picker rests on: a suggestion's id is the id its
    /// type gets when saved, because saving regenerates ids from names. Without
    /// it, a selected suggestion would come back as an unselected chip after a
    /// reload, and re-adding a removed one would not reconnect its entries.
    @Test
    func everySuggestionIsKeyedByTheIDItsTypeGetsOnSave() {
        for suggestion in ActivityCatalog.suggestions {
            #expect(suggestion.id == ActivityType.generateID(from: suggestion.name))
            #expect(suggestion.activityType.id == suggestion.id)
        }
    }

    @Test
    func idsAndNamesAreUnique() {
        let ids = ActivityCatalog.suggestions.map(\.id)
        let names = ActivityCatalog.suggestions.map { $0.name.lowercased() }
        #expect(Set(ids).count == ids.count)
        #expect(Set(names).count == names.count)
    }

    /// A suggestion the validator rejects could be added by one click and then
    /// block saving, with nothing on screen saying which click did it.
    @Test
    func everySuggestionPassesFieldValidation() {
        for suggestion in ActivityCatalog.suggestions {
            #expect(ActivityTypeValidator.validateField(suggestion.activityType) == nil)
        }
    }

    @Test
    func suggestionLookupIsByID() {
        #expect(ActivityCatalog.suggestion(id: "code_review")?.name == "Code Review")
        #expect(ActivityCatalog.suggestion(id: "not_a_suggestion") == nil)
    }

    /// Ids Zeit used to ship that the catalog no longer offers. A user who still
    /// has one keeps it — their entries reference it — but it is not suggested
    /// back to them.
    @Test(arguments: [
        "slack", "zoom_meeting", "professional_development", "personal_ai_use",
        "personal_calendar", "youtube_entertainment", "work_browsing",
    ])
    func droppedIDsAreNotOffered(id: String) {
        #expect(ActivityCatalog.suggestion(id: id) == nil)
    }

    // MARK: - Twins

    /// The pairs that look identical on screen. Flagging them is the only way a
    /// user learns that the shipped description is not enough.
    @Test
    func theCrossGroupTwinsAreFlagged() {
        let twins = ActivityCatalog.suggestions.filter(\.isTwin).map(\.id)

        #expect(
            Set(twins) == [
                "work_coding", "project_coding",
                "work_email", "personal_email",
                "work_research",
                "code_review",
                "work_docs_writing", "project_writing_design",
            ]
        )
    }

    @Test
    func isTwin_readsTheCatalogAndIgnoresUserTypes() {
        let twin = ActivityCatalog.suggestion(id: "work_coding")!.activityType
        let plain = ActivityCatalog.suggestion(id: "meetings")!.activityType
        let mine = ActivityType(
            id: "my_thing", name: "My Thing", description: "d", group: .work
        )

        #expect(ActivityCatalog.isTwin(twin))
        #expect(!ActivityCatalog.isTwin(plain))
        #expect(!ActivityCatalog.isTwin(mine))
    }

    /// The hint exists to get the user's own specifics into the description. Once
    /// they are there it has nothing left to say.
    @Test
    func needsTwinDetail_stopsOnceTheDescriptionIsTheUsers() {
        var twin = ActivityCatalog.suggestion(id: "project_coding")!.activityType
        #expect(ActivityCatalog.needsTwinDetail(twin))

        twin.description = "Code under ~/repos/me"
        #expect(!ActivityCatalog.needsTwinDetail(twin))
        #expect(ActivityCatalog.isTwin(twin))
    }

    // MARK: - Suggested selections

    /// Onboarding's two answers, against the pre-selection table in the spec.
    @Test
    func theSuggestedSelectionForWork() {
        #expect(
            ActivityCatalog.suggestedSelectionIDs(for: .work) == [
                "work_coding", "code_review", "meetings", "work_chat", "work_email",
                "tickets_planning", "work_research",
                "personal_browsing", "social_media", "video_youtube", "personal_messaging",
            ]
        )
    }

    @Test
    func theSuggestedSelectionForPersonalProjects() {
        #expect(
            ActivityCatalog.suggestedSelectionIDs(for: .personalProjects) == [
                "project_coding", "learning", "reading", "project_writing_design",
                "work_chat", "work_email", "meetings",
                "personal_browsing", "social_media", "video_youtube", "entertainment",
                "personal_messaging",
            ]
        )
    }

    /// Editing is meant to be mostly subtractive, so a selection starts inside
    /// the band that classifies best rather than at the cap.
    @Test(arguments: ActivityGroup.allCases)
    func everySuggestedSelectionIsAUsableStartingPoint(primaryGroup: ActivityGroup) {
        let selection = ActivityCatalog.suggestedSelection(for: primaryGroup)

        #expect(ActivityCatalog.comfortableRange.contains(selection.count))
        #expect(selection.contains { $0.group == primaryGroup })
        #expect(ActivityTypeValidator.validateAll(selection, primaryGroup: primaryGroup).isEmpty)
    }

    /// Work gets checked from the personal machine and personal browsing happens
    /// on the work laptop, so no selection is single-group.
    @Test(arguments: ActivityGroup.goals)
    func aSuggestedSelectionSpansGroups(primaryGroup: ActivityGroup) {
        let groups = Set(ActivityCatalog.suggestedSelection(for: primaryGroup).map(\.group))
        #expect(groups.count > 1)
        #expect(groups.contains(.personal))
    }

    /// A pre-selection is written as ids, so a typo would silently drop a type
    /// from the picker instead of failing anywhere.
    @Test(arguments: ActivityGroup.allCases)
    func everyPreselectedIDResolvesToASuggestion(primaryGroup: ActivityGroup) {
        let ids = ActivityCatalog.suggestedSelectionIDs(for: primaryGroup)
        let selection = ActivityCatalog.suggestedSelection(for: primaryGroup)

        #expect(selection.count == ids.count)
        #expect(Set(selection.map(\.id)) == ids)
        for type in selection {
            #expect(ActivityCatalog.suggestion(id: type.id)?.activityType == type)
        }
    }

    /// Catalog order, not the order the id set happened to be written in: the
    /// picker's rows must not shuffle between launches.
    @Test
    func aSuggestedSelectionFollowsCatalogOrder() {
        let ids = ActivityCatalog.suggestedSelection(for: .work).map(\.id)
        let catalogOrder = ActivityCatalog.suggestions.map(\.id).filter { ids.contains($0) }
        #expect(ids == catalogOrder)
    }

    // MARK: - Starter set

    /// What the machine where nobody opens the GUI runs on. It cannot read the
    /// config, so it has to be usable without knowing what the machine is for.
    @Test
    func theStarterSetIsSmallAndCoversEveryGroup() {
        #expect(ActivityCatalog.comfortableRange.contains(ActivityCatalog.starterSet.count))

        let groups = Set(ActivityCatalog.starterSet.map(\.group))
        #expect(groups == Set(ActivityGroup.allCases))
    }

    @Test
    func theStarterSetIsDrawnFromTheCatalog() {
        for type in ActivityCatalog.starterSet {
            #expect(ActivityCatalog.suggestion(id: type.id)?.activityType == type)
        }
    }

    /// It is written before anyone has answered the onboarding question, so it
    /// has to validate against whichever group ends up primary.
    @Test(arguments: ActivityGroup.allCases)
    func theStarterSetValidatesAgainstAnyPrimaryGroup(primaryGroup: ActivityGroup) {
        #expect(
            ActivityTypeValidator.validateAll(
                ActivityCatalog.starterSet, primaryGroup: primaryGroup
            ).isEmpty
        )
    }
}
