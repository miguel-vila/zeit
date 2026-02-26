import Foundation
import os

private let logger = Logger(subsystem: "com.zeit", category: "DaySummarizer")

/// Result of summarizing a day's activities
struct DaySummary: Sendable {
    let summary: String
    let objectivesAlignment: String?
    let percentagesBreakdown: String
    let startTime: Date
    let endTime: Date
}

/// Summarizes a day's activities using an LLM
struct DaySummarizer: Sendable {
    private let provider: LLMProvider

    init(provider: LLMProvider) {
        self.provider = provider
    }

    /// Summarize a day's activities, optionally considering objectives.
    ///
    /// - Parameters:
    ///   - activities: All activity entries for the day.
    ///   - objectives: Optional day objectives.
    /// - Returns: A `DaySummary`, or `nil` if there are no non-idle activities.
    func summarize(
        activities: [ActivityEntry],
        objectives: DayObjectives? = nil,
        activityTypes: [ActivityType] = ActivityType.defaultTypes
    ) async throws -> DaySummary? {
        let nonIdle = activities.filter { $0.activity != .idle }

        guard !nonIdle.isEmpty else {
            return nil
        }

        logger.info("Starting summarization with \(nonIdle.count) non-idle activities")

        // Build condensed summary with grouped activities
        let condensed = buildCondensedSummary(from: activities, activityTypes: activityTypes)

        logger.info(
            "Condensed \(condensed.originalEntryCount) activities into \(condensed.condensedEntryCount) groups"
        )

        // Format condensed activities for prompt
        let activitiesText = condensed.groups
            .map { formatGroup($0) }
            .joined(separator: "\n")

        // Format percentage breakdown
        let percentageText = condensed.percentageBreakdown
            .map { "- \($0.activity.displayName.lowercased()): \(String(format: "%.1f", $0.percentage))%" }
            .joined(separator: "\n")

        // Build the prompt
        let objectivesTuple: (main: String, secondary: [String])?
        if let obj = objectives {
            objectivesTuple = (main: obj.mainObjective, secondary: obj.secondaryObjectives)
        } else {
            objectivesTuple = nil
        }

        let prompt = Prompts.daySummary(
            activitiesText: activitiesText,
            percentageBreakdown: percentageText,
            objectives: objectivesTuple
        )

        logger.debug("Day summarization prompt:\n\(prompt)")

        let schema = Self.summarySchema(hasObjectives: objectives != nil)

        let responseText = try await provider.generateStructured(
            prompt: prompt,
            schema: schema,
            temperature: 0.7
        )

        let parsed = try parseSummaryResponse(responseText)

        let isoFormatter = ISO8601DateFormatter()
        let startTime = isoFormatter.date(from: nonIdle[0].timestamp) ?? Date()
        let endTime = isoFormatter.date(from: nonIdle[nonIdle.count - 1].timestamp) ?? Date()

        logger.debug("Day summary generated")
        return DaySummary(
            summary: parsed.summary,
            objectivesAlignment: parsed.objectivesAlignment,
            percentagesBreakdown: percentageText,
            startTime: startTime,
            endTime: endTime
        )
    }

    // MARK: - JSON Schema

    private static func summarySchema(hasObjectives: Bool) -> [String: Any] {
        var properties: [String: Any] = [
            "summary": [
                "type": "string",
                "description": "A concise 2-3 sentence narrative summary of the day's activities"
            ]
        ]
        var required = ["summary"]

        if hasObjectives {
            properties["objectives_alignment"] = [
                "type": "string",
                "description": "1-2 sentence assessment of how well the day's activities aligned with the stated objectives"
            ]
            required.append("objectives_alignment")
        }

        return [
            "type": "object",
            "properties": properties,
            "required": required
        ]
    }

    // MARK: - Response Parsing

    private func parseSummaryResponse(_ response: String) throws -> SummaryResponse {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            throw DaySummarizerError.invalidResponse("Could not encode response as UTF-8")
        }
        do {
            return try JSONDecoder().decode(SummaryResponse.self, from: data)
        } catch {
            throw DaySummarizerError.invalidResponse(
                "Failed to parse summary: \(error.localizedDescription). Response was: \(trimmed.prefix(200))"
            )
        }
    }

    // MARK: - Formatting

    private func formatTimeRange(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        if start == end {
            return formatter.string(from: start)
        }
        return "\(formatter.string(from: start))-\(formatter.string(from: end))"
    }

    private func formatGroup(_ group: ActivityGroup) -> String {
        let timeRange = formatTimeRange(start: group.startTime, end: group.endTime)
        let reasoning = group.reasonings.isEmpty
            ? "No description"
            : group.reasonings.joined(separator: "; ")
        let activityName = group.activity.displayName.lowercased()
        return "\(timeRange) - \(activityName) (\(group.durationMinutes) min): \"\(reasoning)\""
    }
}

// MARK: - Response Models

private struct SummaryResponse: Decodable {
    let summary: String
    let objectivesAlignment: String?

    enum CodingKeys: String, CodingKey {
        case summary
        case objectivesAlignment = "objectives_alignment"
    }
}

// MARK: - Errors

enum DaySummarizerError: LocalizedError {
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let message):
            return "Invalid summary response: \(message)"
        }
    }
}
