import Foundation

/// Identifies the user's current activity by capturing screenshots and using LLM
final class ActivityIdentifier: @unchecked Sendable {
    private let visionModel: String
    private let textModel: String
    private let textProvider: String

    init(
        visionModel: String = "qwen3-vl:4b",
        textModel: String = "qwen3:8b",
        textProvider: String = "ollama"
    ) {
        self.visionModel = visionModel
        self.textModel = textModel
        self.textProvider = textProvider
    }

    /// Capture screenshots and identify the current activity
    func identifyCurrentActivity() async throws -> IdentificationResult {
        // 1. Capture screenshots from all monitors
        let screenshots = try ScreenCapture.captureAllMonitors()
        defer { ScreenCapture.cleanup(screenshots: screenshots) }

        // 2. Determine active screen
        let activeScreen = ActiveWindow.getActiveScreenNumber()

        // 3. Load images as base64
        var base64Images: [String] = []
        for screenNum in screenshots.keys.sorted() {
            if let url = screenshots[screenNum] {
                let base64 = try ScreenCapture.loadAsBase64(url: url)
                base64Images.append(base64)
            }
        }

        guard !base64Images.isEmpty else {
            throw ActivityIdentifierError.noScreenshotsCaptured
        }

        // 4. Call vision model to describe the screens
        let descriptionPrompt = Prompts.visionDescription(
            activeScreen: activeScreen,
            screenCount: screenshots.count
        )

        let visionResponse: (response: String, thinking: String?)

        if textProvider == "ollama" {
            // Use Ollama HTTP API (legacy path, for when Ollama is available)
            let visionClient = OllamaClient(model: visionModel)
            let result = try await visionClient.generateWithVisionThinking(
                prompt: descriptionPrompt,
                images: base64Images,
                temperature: 0
            )
            visionResponse = (result.response, result.thinking)
        } else if let mlxClient = MLXClient(configName: visionModel) {
            // Use on-device MLX inference
            let result = try await mlxClient.generateWithVisionThinking(
                prompt: descriptionPrompt,
                images: base64Images,
                temperature: 0
            )
            visionResponse = (result.response, result.thinking)
        } else {
            // Fallback: try MLX with the vision model info directly
            let mlxClient = MLXClient(modelInfo: MLXModelManager.visionModel)
            let result = try await mlxClient.generateWithVisionThinking(
                prompt: descriptionPrompt,
                images: base64Images,
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

        // 5. Call text model to classify the activity with structured output
        let classificationPrompt = Prompts.activityClassification(
            description: description.mainActivityDescription
        )

        let classificationResponseText: String

        if textProvider == "ollama" {
            // Use Ollama HTTP API
            let textClient = OllamaClient(model: textModel)
            let ollamaResponse = try await textClient.generateStructured(
                prompt: classificationPrompt,
                schema: Self.classificationSchema,
                temperature: 0,
                think: true
            )
            classificationResponseText = ollamaResponse.response
        } else if let mlxClient = MLXClient(configName: textModel) {
            // Use on-device MLX inference
            let mlxResponse = try await mlxClient.generateStructured(
                prompt: classificationPrompt,
                schema: Self.classificationSchema,
                temperature: 0,
                think: true
            )
            classificationResponseText = mlxResponse.response
        } else {
            // Fallback: try MLX with the text model info directly
            let mlxClient = MLXClient(modelInfo: MLXModelManager.textModel)
            let mlxResponse = try await mlxClient.generateStructured(
                prompt: classificationPrompt,
                schema: Self.classificationSchema,
                temperature: 0,
                think: true
            )
            classificationResponseText = mlxResponse.response
        }

        let classification = try parseClassificationResponse(classificationResponseText)

        return IdentificationResult(
            activity: classification.activity,
            reasoning: classification.reasoning,
            description: description.mainActivityDescription,
            activeScreen: activeScreen
        )
    }

    // MARK: - JSON Schemas

    /// JSON Schema for ClassificationResponse
    private static let classificationSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "main_activity": [
                "type": "string",
                "description": "Main detected activity from the screenshot",
                "enum": Activity.allCases.map { $0.rawValue }
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

    // MARK: - Response Parsing

    private func parseClassificationResponse(_ response: String) throws -> ClassificationResponse {
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
        Activity(rawValue: mainActivity) ?? .personalBrowsing
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

    /// Convert to ActivityEntry for database storage
    func toActivityEntry() -> ActivityEntry {
        ActivityEntry(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            activity: activity,
            reasoning: reasoning
        )
    }
}

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
