import Foundation
import os

private let logger = Logger(subsystem: "com.zeit", category: "DaySummarizer")

/// Result of summarizing a day's activities
struct DaySummary: Sendable {
    let summary: String
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
        objectives: DayObjectives? = nil
    ) async throws -> DaySummary? {
        let nonIdle = activities.filter { $0.activity != .idle }

        guard !nonIdle.isEmpty else {
            return nil
        }

        logger.info("Starting summarization with \(nonIdle.count) non-idle activities")

        // Build condensed summary with grouped activities
        let condensed = buildCondensedSummary(from: activities)

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

        let responseText = try await provider.generate(
            prompt: prompt,
            temperature: 0.7,
            jsonMode: false
        )

        let isoFormatter = ISO8601DateFormatter()
        let startTime = isoFormatter.date(from: nonIdle[0].timestamp) ?? Date()
        let endTime = isoFormatter.date(from: nonIdle[nonIdle.count - 1].timestamp) ?? Date()

        logger.debug("Day summary generated")
        return DaySummary(
            summary: responseText,
            percentagesBreakdown: percentageText,
            startTime: startTime,
            endTime: endTime
        )
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
