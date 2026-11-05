import Foundation

/// How an activity type is grouped.
///
/// The group lives on the activity type only, never on an entry: an entry stores
/// its type id, so re-labelling a type re-groups history and there is one source
/// of truth. An entry whose type id is no longer configured has no group and is
/// reported as `unclassifiedLabel`.
enum ActivityGroup: String, Codable, Sendable, CaseIterable {
    case work
    case personalProjects = "personal_projects"
    case personal

    /// Label used wherever an entry's type id is not in the activity type table.
    static let unclassifiedLabel = "Unclassified"

    /// Human-readable name.
    var displayName: String {
        switch self {
        case .work: return "Work"
        case .personalProjects: return "Personal Projects"
        case .personal: return "Personal"
        }
    }

    /// Short label for places with no room for the full name, such as the
    /// menubar's primary-group line ("Projects 41%").
    var shortName: String {
        switch self {
        case .work: return "Work"
        case .personalProjects: return "Projects"
        case .personal: return "Personal"
        }
    }

    /// Section heading used in the classification prompt.
    var promptHeading: String {
        switch self {
        case .work: return "WORK ACTIVITIES"
        case .personalProjects: return "PERSONAL PROJECT ACTIVITIES"
        case .personal: return "PERSONAL ACTIVITIES"
        }
    }
}

// MARK: - Primary group

extension ActivityGroup {
    /// The answers onboarding offers to "What do you want to spend your time on?".
    ///
    /// `personal` is missing on purpose: it is the residual group, measured
    /// against and never for. The asymmetry lives in this copy and in the seed
    /// defaults only — the enum stays flat and settings offers all three.
    static let goals: [ActivityGroup] = [.work, .personalProjects]

    /// Every group, the one the day is judged by first. Wherever the groups are
    /// listed, the primary leads: it is the number the menubar reports and the
    /// section the reader came to read.
    static func allCases(primaryFirst primary: ActivityGroup) -> [ActivityGroup] {
        [primary] + allCases.filter { $0 != primary }
    }

    /// How this group reads as an answer to the onboarding question.
    var goalLabel: String {
        switch self {
        case .work: return "My job"
        case .personalProjects: return "My own projects"
        case .personal: return "Everything else"
        }
    }

    /// What picking this group as primary means, shown under its answer.
    var goalDetail: String {
        switch self {
        case .work: return "Zeit measures the share of your day spent on work"
        case .personalProjects: return "Zeit measures the share of your day spent on side projects"
        case .personal: return "Zeit measures the share of your day spent on personal time"
        }
    }
}

/// An absent group is the Unclassified bucket, so a section heading can be read
/// off an optional group without the caller testing for nil.
extension Optional where Wrapped == ActivityGroup {
    var sectionTitle: String { self?.displayName ?? ActivityGroup.unclassifiedLabel }
}
