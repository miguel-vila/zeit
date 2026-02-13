import Foundation

/// Response from Ollama generate API
struct OllamaResponse {
    let response: String
    let thinking: String?
}

/// Ollama LLM client for local model inference
final class OllamaClient: LLMProvider, VisionLLMProvider, @unchecked Sendable {
    let model: String
    let baseURL: URL

    init(model: String, baseURL: URL = URL(string: "http://localhost:11434")!) {
        self.model = model
        self.baseURL = baseURL
    }

    // MARK: - LLMProvider

    func generate(
        prompt: String,
        temperature: Double? = nil,
        jsonMode: Bool = false
    ) async throws -> String {
        let response = try await generateRaw(
            prompt: prompt,
            images: [],
            temperature: temperature,
            format: jsonMode ? .json : nil,
            think: false
        )
        return response.response
    }

    /// Generate with full JSON schema for structured output
    func generateStructured(
        prompt: String,
        schema: [String: Any],
        temperature: Double? = nil,
        think: Bool = true
    ) async throws -> OllamaResponse {
        try await generateRaw(
            prompt: prompt,
            images: [],
            temperature: temperature,
            format: .schema(schema),
            think: think
        )
    }

    // MARK: - VisionLLMProvider

    func generateWithVision(
        prompt: String,
        images: [String],
        temperature: Double? = nil,
        jsonMode: Bool = false
    ) async throws -> String {
        let response = try await generateRaw(
            prompt: prompt,
            images: images,
            temperature: temperature,
            format: jsonMode ? .json : nil,
            think: false
        )
        return response.response
    }

    /// Generate with vision and full JSON schema for structured output
    func generateWithVisionStructured(
        prompt: String,
        images: [String],
        schema: [String: Any],
        temperature: Double? = nil,
        think: Bool = true
    ) async throws -> OllamaResponse {
        try await generateRaw(
            prompt: prompt,
            images: images,
            temperature: temperature,
            format: .schema(schema),
            think: think
        )
    }

    /// Generate with vision and thinking enabled (for thinking models like qwen3-vl)
    func generateWithVisionThinking(
        prompt: String,
        images: [String],
        temperature: Double? = nil
    ) async throws -> OllamaResponse {
        try await generateRaw(
            prompt: prompt,
            images: images,
            temperature: temperature,
            format: nil,
            think: true
        )
    }

    // MARK: - Format Types

    enum FormatType {
        case json
        case schema([String: Any])

        var value: Any {
            switch self {
            case .json:
                return "json"
            case .schema(let schema):
                return schema
            }
        }
    }

    // MARK: - Raw Generation

    private func generateRaw(
        prompt: String,
        images: [String],
        temperature: Double?,
        format: FormatType?,
        think: Bool
    ) async throws -> OllamaResponse {
        let url = baseURL.appendingPathComponent("api/generate")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300  // 5 minutes for multi-image vision requests

        // Build options dict
        var optionsDict: [String: Any] = ["timeout": 30]
        if let temp = temperature {
            optionsDict["temperature"] = temp
        } else {
            optionsDict["temperature"] = 0
        }

        // Build request body
        var bodyDict: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "options": optionsDict,
        ]

        if !images.isEmpty {
            bodyDict["images"] = images
        }

        // Format can be "json" string or full JSON schema dict
        if let format = format {
            bodyDict["format"] = format.value
        }

        // Explicitly set thinking mode — must always be sent so that
        // thinking models like qwen3-vl don't think by default
        bodyDict["think"] = think

        request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.requestFailed("Invalid response type")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.requestFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        // Parse response - check both response and thinking fields
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.requestFailed("Invalid JSON response")
        }

        let responseText = json["response"] as? String ?? ""
        let thinkingText = json["thinking"] as? String

        // Clean up chat template tokens
        let cleanedResponse = Self.stripChatTemplateTokens(responseText)
        let cleanedThinking = thinkingText.map { Self.stripChatTemplateTokens($0) }

        return OllamaResponse(response: cleanedResponse, thinking: cleanedThinking)
    }

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

}
