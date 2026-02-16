import Foundation

/// Activity categories detected by the tracker.
///
/// This is a string-wrapper struct (not an enum) so it can represent
/// user-defined activity types. It encodes/decodes as a plain JSON string,
/// maintaining backward compatibility with existing data in the database.
struct Activity: Codable, Equatable, Sendable, Hashable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    // MARK: - Codable (plain string encoding for backward compat)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    // MARK: - Static constants for built-in types

    // Personal activities
    static let personalBrowsing = Activity(rawValue: "personal_browsing")
    static let socialMedia = Activity(rawValue: "social_media")
    static let youtubeEntertainment = Activity(rawValue: "youtube_entertainment")
    static let personalEmail = Activity(rawValue: "personal_email")
    static let personalAiUse = Activity(rawValue: "personal_ai_use")
    static let personalFinances = Activity(rawValue: "personal_finances")
    static let professionalDevelopment = Activity(rawValue: "professional_development")
    static let onlineShopping = Activity(rawValue: "online_shopping")
    static let personalCalendar = Activity(rawValue: "personal_calendar")
    static let entertainment = Activity(rawValue: "entertainment")

    // Work activities
    static let slack = Activity(rawValue: "slack")
    static let workEmail = Activity(rawValue: "work_email")
    static let zoomMeeting = Activity(rawValue: "zoom_meeting")
    static let workCoding = Activity(rawValue: "work_coding")
    static let workBrowsing = Activity(rawValue: "work_browsing")
    static let workCalendar = Activity(rawValue: "work_calendar")

    // System
    static let idle = Activity(rawValue: "idle")

    /// Human-readable display name (fallback: title-case the rawValue)
    var displayName: String {
        rawValue
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

/// A single activity entry at a specific timestamp
struct ActivityEntry: Codable, Equatable, Sendable {
    let timestamp: String  // ISO format
    let activity: Activity
    let reasoning: String?
    let description: String?

    /// Parse the timestamp as a Date
    var date: Date? {
        ISO8601DateFormatter().date(from: timestamp)
    }
}

/// All activities for a single day
struct DayRecord: Equatable, Sendable {
    let date: String  // YYYY-MM-DD
    let activities: [ActivityEntry]

    /// Total number of activities
    var count: Int { activities.count }

    /// Filter out idle activities
    var nonIdleActivities: [ActivityEntry] {
        activities.filter { $0.activity != .idle }
    }
}

/// User objectives for a specific day
struct DayObjectives: Equatable, Sendable {
    let date: String
    let mainObjective: String
    let secondaryObjectives: [String]
    let createdAt: String
    let updatedAt: String
}
