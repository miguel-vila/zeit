import SwiftUI

/// How a group is drawn. Every view that renders a group section reads its colour
/// and icon from here, so adding a fourth group needs no view changes.
extension ActivityGroup {
    /// Colour of this group's section, bars and dots.
    var color: Color {
        switch self {
        case .work: return Color(red: 0.2, green: 0.7, blue: 0.6)
        case .personalProjects: return Color(red: 0.95, green: 0.62, blue: 0.2)
        case .personal: return Color(red: 0.6, green: 0.4, blue: 0.8)
        }
    }

    /// SF Symbol shown next to this group's section heading.
    var iconName: String {
        switch self {
        case .work: return "briefcase.fill"
        case .personalProjects: return "hammer.fill"
        case .personal: return "house.fill"
        }
    }

    /// Colour of the Unclassified section, which stands for an absent group.
    static let unclassifiedColor = Color.gray

    /// SF Symbol for the Unclassified section.
    static let unclassifiedIconName = "questionmark.circle.fill"
}

/// An absent group is the Unclassified bucket: an entry whose type id is no
/// longer configured. These let a view style a section without branching on
/// which group it holds.
extension Optional where Wrapped == ActivityGroup {
    var sectionColor: Color { self?.color ?? ActivityGroup.unclassifiedColor }

    var sectionIconName: String { self?.iconName ?? ActivityGroup.unclassifiedIconName }
}
