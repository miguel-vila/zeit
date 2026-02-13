import Foundation

/// Activity categories detected by the tracker.
/// Maps to Python's ExtendedActivity enum.
enum Activity: String, Codable, CaseIterable, Sendable {
    // Personal activities
    case personalBrowsing = "personal_browsing"
    case socialMedia = "social_media"
    case youtubeEntertainment = "youtube_entertainment"
    case personalEmail = "personal_email"
    case personalAiUse = "personal_ai_use"
    case personalFinances = "personal_finances"
    case professionalDevelopment = "professional_development"
    case onlineShopping = "online_shopping"
    case personalCalendar = "personal_calendar"
    case entertainment = "entertainment"

    // Work activities
    case slack = "slack"
    case workEmail = "work_email"
    case zoomMeeting = "zoom_meeting"
    case workCoding = "work_coding"
    case workBrowsing = "work_browsing"
    case workCalendar = "work_calendar"

    // System
    case idle = "idle"

    /// Whether this activity is categorized as work
    var isWork: Bool {
        switch self {
        case .slack, .workEmail, .zoomMeeting, .workCoding, .workBrowsing, .workCalendar:
            return true
        default:
            return false
        }
    }

    /// Human-readable display name
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
