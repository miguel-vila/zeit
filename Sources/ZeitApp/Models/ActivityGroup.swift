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

    /// Section heading used in the classification prompt.
    var promptHeading: String {
        switch self {
        case .work: return "WORK ACTIVITIES"
        case .personalProjects: return "PERSONAL PROJECT ACTIVITIES"
        case .personal: return "PERSONAL ACTIVITIES"
        }
    }
}

/// An absent group is the Unclassified bucket, so a section heading can be read
/// off an optional group without the caller testing for nil.
extension Optional where Wrapped == ActivityGroup {
    var sectionTitle: String { self?.displayName ?? ActivityGroup.unclassifiedLabel }
}
