import Foundation

/// The activity types Zeit *offers*, as opposed to the ones a machine *has*.
///
/// These were one constant before, which made every suggestion a row in the
/// database the first time Zeit ran. They are separate concerns:
///
/// - `suggestions` is larger than any sensible selection and is never written
///   automatically. It is the picker's menu.
/// - `starterSet` is what the machine where nobody opens the GUI runs on. It is
///   small, it covers every group, and it is deliberately independent of
///   `conf.yml`: the database layer must not depend on config to decide what to
///   insert. Onboarding replaces it one screen later.
enum ActivityCatalog {

    /// One entry of the picker's menu.
    ///
    /// A suggestion is keyed by the id its type gets when saved, not by a
    /// hand-written id, so a suggestion already in the selection is still
    /// recognised after a round trip through the database. That is also what
    /// makes unselecting reversible: re-adding a suggestion regenerates the same
    /// id and its old entries reconnect.
    struct Suggestion: Equatable, Sendable, Identifiable {
        let name: String
        let description: String
        let group: ActivityGroup
        /// A cross-group twin: a type that looks identical on screen to one in
        /// another group, so the shipped description cannot separate the pair.
        /// Only content can — which repository, which domain, which account —
        /// and the user is the one who knows it.
        let isTwin: Bool

        var id: String { ActivityType.generateID(from: name) }

        var activityType: ActivityType {
            ActivityType(id: id, name: name, description: description, group: group)
        }

        init(
            _ name: String,
            _ description: String,
            _ group: ActivityGroup,
            twin: Bool = false
        ) {
            self.name = name
            self.description = description
            self.group = group
            self.isTwin = twin
        }
    }

    /// What the picker tells the user about a selection's size.
    ///
    /// Every selected type costs prompt tokens and, past a point, costs
    /// accuracy: a longer list gives the model more near-identical options to
    /// choose between, not finer data.
    static let comfortableRange = 8...14

    /// Hint shown on a twin row, which is the only place the user learns that
    /// the shipped description is not enough on its own.
    static let twinHint =
        "Looks the same on screen as its twin in another group. "
        + "Add what separates them: which repository, which domain, which account."

    // MARK: - Suggestions

    /// 25 suggestions against the 30-type cap, so the menu is always wider than
    /// what fits in a selection.
    static let suggestions: [Suggestion] = [
        // work
        .init("Work Coding", "Code in company repositories, work IDE windows", .work, twin: true),
        .init("Code Review", "Pull requests, diffs, review comments", .work, twin: true),
        .init("Meetings", "Video calls and meetings", .work),
        .init("Work Chat", "Slack, Teams, work group chat", .work),
        .init("Work Email", "Work email client or webmail", .work, twin: true),
        .init("Tickets & Planning", "Jira, boards, sprint planning", .work),
        .init("Work Docs & Writing", "Confluence, specs, design documents", .work, twin: true),
        .init(
            "Work Research", "Work-related documentation and web research", .work, twin: true
        ),
        .init("Work Calendar", "Work calendar and scheduling", .work),

        // personal_projects
        .init(
            "Project Coding",
            "Code in personal repositories and side projects",
            .personalProjects,
            twin: true
        ),
        .init(
            "Project Writing & Design",
            "Notes, design documents and planning for own projects",
            .personalProjects,
            twin: true
        ),
        .init("Learning", "Courses, tutorials, documentation read to learn", .personalProjects),
        .init("Reading", "Technical articles, papers, long-form reading", .personalProjects),
        .init(
            "Writing & Publishing",
            "Blog posts, newsletters, publishing tools",
            .personalProjects
        ),
        .init(
            "Creative Practice",
            "Music, drawing, photography, other making",
            .personalProjects
        ),

        // personal
        .init(
            "Personal Browsing", "General web browsing, not work and not a project", .personal
        ),
        .init("Social Media", "X, Instagram, Reddit, TikTok, LinkedIn feed", .personal),
        .init("Video & YouTube", "YouTube and video watching for leisure", .personal),
        .init("Entertainment", "Games, films, music, streaming", .personal),
        .init("Personal Messaging", "WhatsApp, iMessage, personal chat", .personal),
        .init("Personal Email", "Personal email accounts", .personal, twin: true),
        .init("Finances", "Banking, budgeting, investments", .personal),
        .init("Shopping", "Online shopping and marketplaces", .personal),
        .init("Life Admin", "Appointments, forms, travel, personal calendar", .personal),
        .init("News", "News sites and news apps", .personal),
    ]

    /// The suggestions of `group`, in catalog order.
    static func suggestions(in group: ActivityGroup) -> [Suggestion] {
        suggestions.filter { $0.group == group }
    }

    static func suggestion(id: String) -> Suggestion? {
        suggestions.first { $0.id == id }
    }

    /// Whether this type is a catalog twin, in whatever state its description is
    /// in. A renamed type is no longer the suggestion and is not flagged.
    static func isTwin(_ type: ActivityType) -> Bool {
        suggestion(id: type.id)?.isTwin ?? false
    }

    /// Whether a twin still carries the shipped generic description, which is the
    /// case the hint exists for. Once the user has written their own specifics
    /// the row has nothing left to warn about.
    static func needsTwinDetail(_ type: ActivityType) -> Bool {
        guard let suggestion = suggestion(id: type.id), suggestion.isTwin else { return false }
        return type.description == suggestion.description
    }

    // MARK: - Selections

    /// The types for `ids`, in catalog order so a selection's within-group order
    /// does not depend on how the id list was written.
    private static func types(_ ids: Set<String>) -> [ActivityType] {
        suggestions.filter { ids.contains($0.id) }.map(\.activityType)
    }

    /// The suggested selection for a machine judged by `primaryGroup`: the
    /// primary group's core types, the everyday `personal` types, and a small
    /// `work` set when `work` is not primary — work gets checked from the
    /// personal machine too.
    ///
    /// Editing from here is meant to be mostly subtractive, which is why each
    /// selection lands inside `comfortableRange` rather than at the 30 cap.
    static func suggestedSelection(for primaryGroup: ActivityGroup) -> [ActivityType] {
        types(suggestedSelectionIDs(for: primaryGroup))
    }

    static func suggestedSelectionIDs(for primaryGroup: ActivityGroup) -> Set<String> {
        switch primaryGroup {
        case .work:
            return [
                "work_coding", "code_review", "meetings", "work_chat", "work_email",
                "tickets_planning", "work_research",
                "personal_browsing", "social_media", "video_youtube", "personal_messaging",
            ]
        case .personalProjects:
            return [
                "project_coding", "learning", "reading", "project_writing_design",
                "work_chat", "work_email", "meetings",
                "personal_browsing", "social_media", "video_youtube", "entertainment",
                "personal_messaging",
            ]
        case .personal:
            // Reachable from settings only: onboarding offers the two goals.
            // `personal` is its own core group here, so the everyday personal
            // types grow by the two that only matter when personal time is what
            // the day is measured by.
            return [
                "personal_browsing", "social_media", "video_youtube", "entertainment",
                "personal_messaging", "personal_email", "life_admin",
                "work_chat", "work_email", "meetings",
            ]
        }
    }

    // MARK: - Starter set

    /// Written when the activity type table is empty, for the machine where
    /// nobody opens the GUI.
    ///
    /// It has to stand on its own without knowing what the machine is for, so it
    /// is the overlap of the suggested selections rather than any one of them:
    /// enough work and project types to tell a workday from a side-project
    /// evening, and the personal types that show up on every machine.
    static let starterSet: [ActivityType] = types([
        "work_coding", "meetings", "work_chat", "work_email",
        "project_coding", "learning",
        "personal_browsing", "social_media", "video_youtube", "personal_messaging",
    ])
}
