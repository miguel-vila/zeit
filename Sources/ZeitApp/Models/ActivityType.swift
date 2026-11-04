import Foundation

/// A user-configurable activity type used for classification.
struct ActivityType: Codable, Equatable, Sendable, Identifiable {
    var id: String            // snake_case identifier (e.g. "work_coding")
    var name: String          // display name (e.g. "Work Coding")
    var description: String   // context for LLM (e.g. "Writing code, using IDEs")
    var group: ActivityGroup  // which group this type belongs to
}

// MARK: - ID Generation

extension ActivityType {
    /// Generate a snake_case ID from a display name.
    ///
    /// 1. Lowercase the name
    /// 2. Replace spaces and hyphens with underscores
    /// 3. Remove all non-alphanumeric/underscore characters
    /// 4. Collapse consecutive underscores
    /// 5. Trim leading/trailing underscores
    static func generateID(from name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
            .replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
}

// MARK: - Validation

enum ActivityTypeValidationError: LocalizedError, Equatable {
    case emptyName
    case nameTooLong(String)
    case emptyDescription
    case descriptionTooLong(String)
    case duplicateName(String)
    case reservedID(String)
    case duplicateID(String)
    case noTypes
    case tooManyTypes(Int)
    case noTypesInPrimaryGroup(ActivityGroup)

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Activity name cannot be empty"
        case .nameTooLong(let name):
            return "Activity name '\(name)' must be 50 characters or less"
        case .emptyDescription:
            return "Activity description cannot be empty"
        case .descriptionTooLong(let name):
            return "Description for '\(name)' must be 200 characters or less"
        case .duplicateName(let name):
            return "An activity with this name already exists: '\(name)'"
        case .reservedID(let name):
            return "Activity name '\(name)' conflicts with reserved system type 'idle'"
        case .duplicateID(let id):
            return "Duplicate activity type identifiers found: '\(id)'"
        case .noTypes:
            return "You must have at least one activity type"
        case .tooManyTypes(let count):
            return "Maximum of 30 activity types allowed (currently \(count), to keep LLM prompts within token limits)"
        case .noTypesInPrimaryGroup(let group):
            return "You must have at least one activity type in \(group.displayName), the group your day is measured by"
        }
    }
}

enum ActivityTypeValidator {
    static let maxNameLength = 50
    static let maxDescriptionLength = 200
    static let maxTotalTypes = 30

    /// Validate a single activity type's fields.
    static func validateField(_ type: ActivityType) -> ActivityTypeValidationError? {
        let trimmedName = type.name.trimmingCharacters(in: .whitespaces)
        if trimmedName.isEmpty { return .emptyName }
        if trimmedName.count > maxNameLength { return .nameTooLong(trimmedName) }

        let trimmedDesc = type.description.trimmingCharacters(in: .whitespaces)
        if trimmedDesc.isEmpty { return .emptyDescription }
        if trimmedDesc.count > maxDescriptionLength { return .descriptionTooLong(trimmedName) }

        if ActivityType.generateID(from: trimmedName) == "idle" {
            return .reservedID(trimmedName)
        }

        return nil
    }

    /// Validate a complete selection of activity types against the group the
    /// machine is judged by.
    ///
    /// Groups other than the primary one are not required to be populated: a
    /// machine has a group when it has types in that group. The primary group is
    /// the exception — with nothing in it the menubar number is always zero.
    static func validateAll(
        _ types: [ActivityType],
        primaryGroup: ActivityGroup
    ) -> [ActivityTypeValidationError] {
        var errors: [ActivityTypeValidationError] = []

        if types.isEmpty { errors.append(.noTypes) }
        if types.count > maxTotalTypes { errors.append(.tooManyTypes(types.count)) }

        // Only reported for a non-empty selection: an empty one is already
        // rejected and does not need a second error saying the same thing.
        if !types.isEmpty, !types.contains(where: { $0.group == primaryGroup }) {
            errors.append(.noTypesInPrimaryGroup(primaryGroup))
        }

        // Names are unique across all groups
        var seenNames = Set<String>()
        for type in types {
            let lower = type.name.lowercased()
            if seenNames.contains(lower) {
                errors.append(.duplicateName(type.name))
            }
            seenNames.insert(lower)
        }

        var seenIDs = Set<String>()
        for type in types {
            if seenIDs.contains(type.id) {
                errors.append(.duplicateID(type.id))
            }
            seenIDs.insert(type.id)
        }

        return errors
    }
}

// MARK: - Default Activity Types

extension ActivityType {
    /// The starter set written when the activity type table is empty.
    ///
    /// Auto-seeding exists for the machine where nobody opens the GUI; onboarding
    /// replaces the whole set one screen later.
    static let defaultTypes: [ActivityType] = [
        ActivityType(
            id: "slack",
            name: "Slack",
            description: "Using Slack for work communication",
            group: .work
        ),
        ActivityType(
            id: "work_email",
            name: "Work Email",
            description: "Work email (Outlook, company email)",
            group: .work
        ),
        ActivityType(
            id: "zoom_meeting",
            name: "Zoom Meeting",
            description: "Video calls, meetings",
            group: .work
        ),
        ActivityType(
            id: "work_coding",
            name: "Work Coding",
            description: "Writing code, using IDE",
            group: .work
        ),
        ActivityType(
            id: "work_browsing",
            name: "Work Browsing",
            description: "Work-related web browsing, documentation",
            group: .work
        ),
        ActivityType(
            id: "work_calendar",
            name: "Work Calendar",
            description: "Work calendar/scheduling",
            group: .work
        ),
        ActivityType(
            id: "professional_development",
            name: "Professional Development",
            description: "Learning, courses, tutorials",
            group: .personalProjects
        ),
        ActivityType(
            id: "personal_ai_use",
            name: "Personal AI Use",
            description: "Using AI tools for personal projects",
            group: .personalProjects
        ),
        ActivityType(
            id: "personal_browsing",
            name: "Personal Browsing",
            description: "General web browsing not related to work",
            group: .personal
        ),
        ActivityType(
            id: "social_media",
            name: "Social Media",
            description: "Facebook, Twitter/X, Instagram, TikTok, etc.",
            group: .personal
        ),
        ActivityType(
            id: "youtube_entertainment",
            name: "YouTube Entertainment",
            description: "Watching YouTube for entertainment",
            group: .personal
        ),
        ActivityType(
            id: "personal_email",
            name: "Personal Email",
            description: "Personal email (Gmail, etc.)",
            group: .personal
        ),
        ActivityType(
            id: "personal_finances",
            name: "Personal Finances",
            description: "Banking, budgeting, crypto, investments",
            group: .personal
        ),
        ActivityType(
            id: "online_shopping",
            name: "Online Shopping",
            description: "Amazon, eBay, other shopping sites",
            group: .personal
        ),
        ActivityType(
            id: "personal_calendar",
            name: "Personal Calendar",
            description: "Personal calendar/scheduling",
            group: .personal
        ),
        ActivityType(
            id: "entertainment",
            name: "Entertainment",
            description: "Games, movies, music, streaming",
            group: .personal
        ),
    ]

}
