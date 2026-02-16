import Foundation

/// A user-configurable activity type used for classification.
struct ActivityType: Codable, Equatable, Sendable, Identifiable {
    var id: String           // snake_case identifier (e.g. "work_coding")
    var name: String         // display name (e.g. "Work Coding")
    var description: String  // context for LLM (e.g. "Writing code, using IDEs")
    var isWork: Bool         // true = work, false = personal
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
    case duplicateNameInOtherCategory(String, String)
    case reservedID(String)
    case duplicateID(String)
    case noWorkTypes
    case noPersonalTypes
    case tooManyTypes(Int)

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
        case .duplicateNameInOtherCategory(let name, let category):
            return "An activity with name '\(name)' already exists in \(category)"
        case .reservedID(let name):
            return "Activity name '\(name)' conflicts with reserved system type 'idle'"
        case .duplicateID(let id):
            return "Duplicate activity type identifiers found: '\(id)'"
        case .noWorkTypes:
            return "You must have at least one work activity type"
        case .noPersonalTypes:
            return "You must have at least one personal activity type"
        case .tooManyTypes(let count):
            return "Maximum of 30 activity types allowed (currently \(count), to keep LLM prompts within token limits)"
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

    /// Validate a complete list of activity types.
    static func validateAll(
        work: [ActivityType],
        personal: [ActivityType]
    ) -> [ActivityTypeValidationError] {
        var errors: [ActivityTypeValidationError] = []

        if work.isEmpty { errors.append(.noWorkTypes) }
        if personal.isEmpty { errors.append(.noPersonalTypes) }

        let total = work.count + personal.count
        if total > maxTotalTypes { errors.append(.tooManyTypes(total)) }

        // Check duplicates within each category
        var workNames = Set<String>()
        for type in work {
            let lower = type.name.lowercased()
            if workNames.contains(lower) {
                errors.append(.duplicateName(type.name))
            }
            workNames.insert(lower)
        }

        var personalNames = Set<String>()
        for type in personal {
            let lower = type.name.lowercased()
            if personalNames.contains(lower) {
                errors.append(.duplicateName(type.name))
            }
            personalNames.insert(lower)
        }

        // Check duplicates across categories
        for name in workNames {
            if personalNames.contains(name) {
                errors.append(.duplicateNameInOtherCategory(name, "personal"))
            }
        }

        // Check duplicate IDs
        var seenIDs = Set<String>()
        for type in work + personal {
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
    static let defaultTypes: [ActivityType] = defaultPersonalTypes + defaultWorkTypes

    static let defaultPersonalTypes: [ActivityType] = [
        ActivityType(
            id: "personal_browsing",
            name: "Personal Browsing",
            description: "General web browsing not related to work",
            isWork: false
        ),
        ActivityType(
            id: "social_media",
            name: "Social Media",
            description: "Facebook, Twitter/X, Instagram, TikTok, etc.",
            isWork: false
        ),
        ActivityType(
            id: "youtube_entertainment",
            name: "YouTube Entertainment",
            description: "Watching YouTube for entertainment",
            isWork: false
        ),
        ActivityType(
            id: "personal_email",
            name: "Personal Email",
            description: "Personal email (Gmail, etc.)",
            isWork: false
        ),
        ActivityType(
            id: "personal_ai_use",
            name: "Personal AI Use",
            description: "Using AI tools for personal projects",
            isWork: false
        ),
        ActivityType(
            id: "personal_finances",
            name: "Personal Finances",
            description: "Banking, budgeting, crypto, investments",
            isWork: false
        ),
        ActivityType(
            id: "professional_development",
            name: "Professional Development",
            description: "Learning, courses, tutorials",
            isWork: false
        ),
        ActivityType(
            id: "online_shopping",
            name: "Online Shopping",
            description: "Amazon, eBay, other shopping sites",
            isWork: false
        ),
        ActivityType(
            id: "personal_calendar",
            name: "Personal Calendar",
            description: "Personal calendar/scheduling",
            isWork: false
        ),
        ActivityType(
            id: "entertainment",
            name: "Entertainment",
            description: "Games, movies, music, streaming",
            isWork: false
        ),
    ]

    static let defaultWorkTypes: [ActivityType] = [
        ActivityType(
            id: "slack",
            name: "Slack",
            description: "Using Slack for work communication",
            isWork: true
        ),
        ActivityType(
            id: "work_email",
            name: "Work Email",
            description: "Work email (Outlook, company email)",
            isWork: true
        ),
        ActivityType(
            id: "zoom_meeting",
            name: "Zoom Meeting",
            description: "Video calls, meetings",
            isWork: true
        ),
        ActivityType(
            id: "work_coding",
            name: "Work Coding",
            description: "Writing code, using IDE",
            isWork: true
        ),
        ActivityType(
            id: "work_browsing",
            name: "Work Browsing",
            description: "Work-related web browsing, documentation",
            isWork: true
        ),
        ActivityType(
            id: "work_calendar",
            name: "Work Calendar",
            description: "Work calendar/scheduling",
            isWork: true
        ),
    ]
}
