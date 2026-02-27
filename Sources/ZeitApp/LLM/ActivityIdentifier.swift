import Foundation

/// Identifies the user's current activity by capturing screenshots and using LLM
final class ActivityIdentifier: @unchecked Sendable {
    private let visionModel: String
    private let textModel: String
    private let textProvider: String

    init(
        visionModel: String = "qwen3-vl:4b",
        textModel: String = "qwen3:8b",
        textProvider: String = "mlx"
    ) {
        self.visionModel = visionModel
        self.textModel = textModel
        self.textProvider = textProvider
    }

    /// Capture screenshots and identify the current activity
    /// - Parameter keepScreenshots: If true, don't delete screenshots after processing
    /// - Parameter sample: If true, collect all artifacts and write a sample to disk
    func identifyCurrentActivity(keepScreenshots: Bool = false, debug: Bool = false, sample: Bool = false) async throws -> IdentificationResult {
        // 1. Capture screenshots from all monitors
        let screenshots = try ScreenCapture.captureAllMonitors()
        let shouldKeep = keepScreenshots || sample
        defer {
            if !shouldKeep {
                ScreenCapture.cleanup(screenshots: screenshots)
            }
        }

        // 2. Determine active screen and frontmost app
        let screenDebugInfo = debug ? ActiveWindow.getScreenDebugInfo() : nil
        let activeScreen = try ActiveWindow.getActiveScreenNumber()
        let frontmostApp = ActiveWindow.getFrontmostAppName()

        // 3. Collect screenshot URLs in screen order
        let imageURLs = screenshots.keys.sorted().compactMap { screenshots[$0] }

        guard !imageURLs.isEmpty else {
            throw ActivityIdentifierError.noScreenshotsCaptured
        }

        // 4. Call vision model to describe the screens
        let descriptionPrompt = Prompts.visionDescription(
            activeScreen: activeScreen,
            screenCount: screenshots.count,
            frontmostApp: frontmostApp
        )

        let visionResponse: (response: String, thinking: String?)

        if let mlxClient = MLXClient(configName: visionModel) {
            let result = try await mlxClient.generateWithVisionThinking(
                prompt: descriptionPrompt,
                imageURLs: imageURLs,
                temperature: 0
            )
            visionResponse = (result.response, result.thinking)
        } else {
            // Fallback: try MLX with the vision model info directly
            let mlxClient = MLXClient(modelInfo: MLXModelManager.visionModel)
            let result = try await mlxClient.generateWithVisionThinking(
                prompt: descriptionPrompt,
                imageURLs: imageURLs,
                temperature: 0
            )
            visionResponse = (result.response, result.thinking)
        }

        // Use the clean response (thinking is separated out)
        let description = DescriptionResponse(
            thinking: visionResponse.thinking,
            primaryScreen: activeScreen,
            mainActivityDescription: visionResponse.response.trimmingCharacters(in: .whitespacesAndNewlines),
            secondaryContext: nil
        )

        // 5. Fetch activity types from DB for dynamic classification
        let db = try DatabaseHelper()
        let activityTypes = try await db.getActivityTypes()

        // 6. Call text model to classify the activity with structured output
        let classificationPrompt = Prompts.activityClassification(
            description: description.mainActivityDescription,
            activityTypes: activityTypes
        )

        let schema = Self.classificationSchema(for: activityTypes)

        let classificationResult: MLXResponse

        if let mlxClient = MLXClient(configName: textModel) {
            classificationResult = try await mlxClient.generateStructuredMLX(
                prompt: classificationPrompt,
                schema: schema,
                temperature: 0,
                think: true
            )
        } else {
            // Fallback: try MLX with the text model info directly
            let mlxClient = MLXClient(modelInfo: MLXModelManager.textModel)
            classificationResult = try await mlxClient.generateStructuredMLX(
                prompt: classificationPrompt,
                schema: schema,
                temperature: 0,
                think: true
            )
        }

        let classification = try parseClassificationResponse(classificationResult.response, activityTypes: activityTypes)

        #if DEBUG
        // Write sample artifacts to disk if requested
        if sample {
            let sampleData = SampleData(
                timestamp: Date(),
                activeScreen: activeScreen,
                frontmostApp: frontmostApp,
                screenshotURLs: imageURLs,
                visionModel: visionModel,
                visionPrompt: descriptionPrompt,
                visionThinking: visionResponse.thinking,
                visionResponse: visionResponse.response,
                classificationModel: textModel,
                classificationProvider: textProvider,
                classificationPrompt: classificationPrompt,
                classificationThinking: classificationResult.thinking,
                classificationResponse: classificationResult.response,
                parsedActivity: classification.mainActivity,
                parsedReasoning: classification.reasoning
            )
            let sampleDir = try SampleWriter.write(sampleData)
            print("Sample written to: \(sampleDir.path)")
        }
        #endif

        return IdentificationResult(
            activity: classification.activity,
            reasoning: classification.reasoning,
            description: description.mainActivityDescription,
            activeScreen: activeScreen,
            screenshotPaths: shouldKeep ? screenshots.keys.sorted().compactMap { screenshots[$0] } : nil,
            screenDebugInfo: screenDebugInfo
        )
    }

    // MARK: - JSON Schemas

    /// Build a JSON schema dynamically from the configured activity types.
    private static func classificationSchema(for types: [ActivityType]) -> [String: Any] {
        let validActivities = types.map(\.id) + ["idle"]
        return [
            "type": "object",
            "properties": [
                "main_activity": [
                    "type": "string",
                    "description": "Main detected activity from the screenshot",
                    "enum": validActivities
                ],
                "reasoning": [
                    "type": "string",
                    "description": "The reasoning behind the selection of the main activity"
                ],
                "secondary_context": [
                    "type": ["string", "null"],
                    "description": "Brief description of activities visible on secondary screens"
                ]
            ],
            "required": ["main_activity", "reasoning"]
        ]
    }

    // MARK: - Response Parsing

    private func parseClassificationResponse(_ response: String, activityTypes: [ActivityType]) throws -> ClassificationResponse {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            throw ActivityIdentifierError.invalidResponse("Could not encode response as UTF-8")
        }

        do {
            let decoded = try JSONDecoder().decode(ClassificationResponse.self, from: data)
            return decoded
        } catch {
            throw ActivityIdentifierError.invalidResponse("Failed to parse classification: \(error.localizedDescription). Response was: \(trimmed.prefix(200))")
        }
    }
}

// MARK: - Response Models

struct DescriptionResponse {
    let thinking: String?
    let primaryScreen: Int
    let mainActivityDescription: String
    let secondaryContext: String?
}

private struct ClassificationResponse: Decodable {
    let thinking: String?
    let mainActivity: String
    let reasoning: String
    let secondaryContext: String?

    var activity: Activity {
        Activity(rawValue: mainActivity)
    }

    enum CodingKeys: String, CodingKey {
        case thinking
        case mainActivity = "main_activity"
        case reasoning
        case secondaryContext = "secondary_context"
    }
}

// MARK: - Result

struct IdentificationResult {
    let activity: Activity
    let reasoning: String?
    let description: String
    let activeScreen: Int
    let screenshotPaths: [URL]?
    let screenDebugInfo: String?

    /// Convert to ActivityEntry for database storage
    func toActivityEntry() -> ActivityEntry {
        ActivityEntry(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            activity: activity,
            reasoning: reasoning,
            description: description
        )
    }
}

// MARK: - Sample Data

#if DEBUG
struct SampleData {
    let timestamp: Date
    let activeScreen: Int
    let frontmostApp: String?
    let screenshotURLs: [URL]

    // Vision stage
    let visionModel: String
    let visionPrompt: String
    let visionThinking: String?
    let visionResponse: String

    // Classification stage
    let classificationModel: String
    let classificationProvider: String
    let classificationPrompt: String
    let classificationThinking: String?
    let classificationResponse: String

    // Final result
    let parsedActivity: String
    let parsedReasoning: String?
}
#endif

// MARK: - Errors

enum ActivityIdentifierError: LocalizedError {
    case noScreenshotsCaptured
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .noScreenshotsCaptured:
            return "Failed to capture any screenshots"
        case .invalidResponse(let message):
            return "Invalid LLM response: \(message)"
        }
    }
}
