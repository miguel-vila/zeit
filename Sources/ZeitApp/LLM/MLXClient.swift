import Foundation
import MLXLMCommon
import MLXLLM
import MLXVLM
import os

private let logger = Logger(subsystem: "com.zeit", category: "MLXClient")

/// Response from MLX model generation
struct MLXResponse {
    let response: String
    let thinking: String?
}

/// MLX-based LLM client for on-device model inference via Apple Silicon.
final class MLXClient: LLMProvider, VisionLLMProvider, @unchecked Sendable {
    let modelInfo: MLXModelInfo

    init(modelInfo: MLXModelInfo) {
        self.modelInfo = modelInfo
    }

    // MARK: - Convenience initializers

    /// Create an MLXClient from a config name like "qwen3-vl:4b" or "qwen3:8b"
    convenience init?(configName: String) {
        guard let info = MLXModelManager.modelInfo(forConfigName: configName) else {
            return nil
        }
        self.init(modelInfo: info)
    }

    // MARK: - LLMProvider

    func generate(
        prompt: String,
        temperature: Double? = nil,
        jsonMode: Bool = false
    ) async throws -> String {
        let container = try await MLXModelManager.shared.loadModel(modelInfo)

        let result = try await container.perform { context in
            let input = UserInput(prompt: prompt)
            let lmInput = try await context.processor.prepare(input: input)

            let params = GenerateParameters(
                maxTokens: 2048,
                temperature: Float(temperature ?? 0)
            )

            let genResult = try MLXLMCommon.generate(
                input: lmInput,
                parameters: params,
                context: context
            ) { tokens in
                tokens.count >= 2048 ? .stop : .more
            }

            return genResult.output
        }

        let cleaned = Self.stripChatTemplateTokens(result)
        return cleaned
    }

    // MARK: - VisionLLMProvider

    func generateWithVision(
        prompt: String,
        images: [String],
        temperature: Double? = nil,
        jsonMode: Bool = false
    ) async throws -> String {
        let response = try await generateWithVisionFull(
            prompt: prompt,
            images: images,
            temperature: temperature
        )
        return response.response
    }

    // MARK: - Extended Methods

    /// Generate structured output (JSON) — for text models
    func generateStructured(
        prompt: String,
        schema: [String: Any],
        temperature: Double? = nil,
        think: Bool = true
    ) async throws -> MLXResponse {
        // For structured output, we append the schema hint to the prompt
        // since MLX doesn't have native JSON schema enforcement
        let enhancedPrompt: String
        if let schemaData = try? JSONSerialization.data(withJSONObject: schema),
           let schemaStr = String(data: schemaData, encoding: .utf8) {
            enhancedPrompt = prompt + "\n\nRespond with valid JSON matching this schema:\n\(schemaStr)"
        } else {
            enhancedPrompt = prompt
        }

        let container = try await MLXModelManager.shared.loadModel(modelInfo)

        let result = try await container.perform { context in
            let input = UserInput(prompt: enhancedPrompt)
            let lmInput = try await context.processor.prepare(input: input)

            let params = GenerateParameters(
                maxTokens: 2048,
                temperature: Float(temperature ?? 0)
            )

            let genResult = try MLXLMCommon.generate(
                input: lmInput,
                parameters: params,
                context: context
            ) { tokens in
                tokens.count >= 2048 ? .stop : .more
            }

            return genResult.output
        }

        let cleaned = Self.stripChatTemplateTokens(result)
        let (thinking, response) = Self.separateThinking(from: cleaned)

        // Try to extract just the JSON from the response
        let jsonResponse = Self.extractJSON(from: response)

        return MLXResponse(response: jsonResponse, thinking: thinking)
    }

    /// Generate with vision and thinking enabled (for vision models)
    func generateWithVisionThinking(
        prompt: String,
        images: [String],
        temperature: Double? = nil
    ) async throws -> MLXResponse {
        try await generateWithVisionFull(
            prompt: prompt,
            images: images,
            temperature: temperature
        )
    }

    // MARK: - Internal

    private func generateWithVisionFull(
        prompt: String,
        images: [String],
        temperature: Double?
    ) async throws -> MLXResponse {
        let container = try await MLXModelManager.shared.loadModel(modelInfo)

        // Convert base64 images to UserInput.Image
        let userImages: [UserInput.Image] = try images.compactMap { base64String in
            guard let data = Data(base64Encoded: base64String) else {
                logger.warning("Failed to decode base64 image")
                return nil
            }

            // Write to a temp file so we can use URL-based input
            let tempDir = FileManager.default.temporaryDirectory
            let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".jpg")
            try data.write(to: tempFile)
            return .url(tempFile)
        }

        let result = try await container.perform { context in
            let processing = UserInput.Processing(resize: CGSize(width: 1280, height: 1280))
            let input = UserInput(
                prompt: .chat([.user(prompt, images: userImages, videos: [])]),
                images: userImages,
                processing: processing
            )
            let lmInput = try await context.processor.prepare(input: input)

            let params = GenerateParameters(
                maxTokens: 2048,
                temperature: Float(temperature ?? 0)
            )

            let genResult = try MLXLMCommon.generate(
                input: lmInput,
                parameters: params,
                context: context
            ) { tokens in
                tokens.count >= 2048 ? .stop : .more
            }

            return genResult.output
        }

        // Clean up temp files
        for image in userImages {
            if case .url(let url) = image {
                try? FileManager.default.removeItem(at: url)
            }
        }

        let cleaned = Self.stripChatTemplateTokens(result)
        let (thinking, response) = Self.separateThinking(from: cleaned)

        return MLXResponse(response: response, thinking: thinking)
    }

    // MARK: - Text Cleanup

    /// Strip Qwen chat template tokens that can leak into responses
    private static func stripChatTemplateTokens(_ text: String) -> String {
        var result = text
        let tokens = [
            "<|im_start|>", "<|im_end|>", "<|im_sep|>",
            "<|endoftext|>", "<|fim_prefix|>", "<|fim_middle|>", "<|fim_suffix|>",
        ]
        for token in tokens {
            result = result.replacingOccurrences(of: token, with: "")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Separate thinking tokens from the actual response.
    /// Qwen3 uses <think>...</think> tags to wrap thinking content.
    private static func separateThinking(from text: String) -> (thinking: String?, response: String) {
        let thinkPattern = #"<think>(.*?)</think>"#
        guard let regex = try? NSRegularExpression(pattern: thinkPattern, options: .dotMatchesLineSeparators) else {
            return (nil, text)
        }

        let range = NSRange(text.startIndex..., in: text)
        var thinkingParts: [String] = []

        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            if let matchRange = match?.range(at: 1),
               let swiftRange = Range(matchRange, in: text) {
                thinkingParts.append(String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        let response = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let thinking = thinkingParts.isEmpty ? nil : thinkingParts.joined(separator: "\n")
        return (thinking, response)
    }

    /// Extract JSON from a response that may contain surrounding text
    private static func extractJSON(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // If it already looks like JSON, return as-is
        if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
            return trimmed
        }

        // Try to find JSON in code blocks
        if let codeBlockRange = trimmed.range(of: "```json\n"),
           let endRange = trimmed.range(of: "\n```", range: codeBlockRange.upperBound..<trimmed.endIndex) {
            return String(trimmed[codeBlockRange.upperBound..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Try to find a JSON object anywhere in the text
        if let start = trimmed.firstIndex(of: "{"),
           let end = trimmed.lastIndex(of: "}") {
            return String(trimmed[start...end])
        }

        return trimmed
    }
}
