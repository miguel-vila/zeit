import Foundation

/// Protocol for LLM text generation providers
protocol LLMProvider: Sendable {
    /// Generate a response for the given prompt
    /// - Parameters:
    ///   - prompt: The prompt to send to the model
    ///   - temperature: Optional temperature for response randomness
    ///   - jsonMode: Whether to request JSON-formatted output
    /// - Returns: The generated text response
    func generate(
        prompt: String,
        temperature: Double?,
        jsonMode: Bool
    ) async throws -> String

    /// Generate a structured JSON response matching the given schema
    /// - Parameters:
    ///   - prompt: The prompt to send to the model
    ///   - schema: JSON Schema dictionary describing the expected output
    ///   - temperature: Optional temperature for response randomness
    /// - Returns: The generated JSON string
    func generateStructured(
        prompt: String,
        schema: [String: Any],
        temperature: Double?
    ) async throws -> String
}

// MARK: - Default Implementation

extension LLMProvider {
    func generateStructured(
        prompt: String,
        schema: [String: Any],
        temperature: Double?
    ) async throws -> String {
        // Default: append schema to prompt and use jsonMode
        var enhancedPrompt = prompt
        if let schemaData = try? JSONSerialization.data(withJSONObject: schema),
           let schemaStr = String(data: schemaData, encoding: .utf8) {
            enhancedPrompt += "\n\nRespond with valid JSON matching this schema:\n\(schemaStr)"
        }
        return try await generate(prompt: enhancedPrompt, temperature: temperature, jsonMode: true)
    }
}

/// Factory for creating LLM providers based on configuration
enum LLMProviderFactory {
    /// Create an LLM provider based on the provider type
    /// - Parameters:
    ///   - provider: Provider type ("mlx" or "openai")
    ///   - model: Model name to use (config name like "qwen3:8b" for mlx)
    /// - Returns: An LLM provider instance
    static func create(provider: String, model: String) throws -> LLMProvider {
        switch provider.lowercased() {
        case "mlx":
            guard let client = MLXClient(configName: model) else {
                throw LLMError.unknownProvider("MLX model not found: \(model)")
            }
            return client

        case "openai":
            guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] else {
                throw LLMError.missingAPIKey("OPENAI_API_KEY environment variable required for OpenAI provider")
            }
            return OpenAIClient(model: model, apiKey: apiKey)

        default:
            throw LLMError.unknownProvider(provider)
        }
    }
}

// MARK: - Errors

enum LLMError: LocalizedError {
    case missingAPIKey(String)
    case unknownProvider(String)
    case requestFailed(String)
    case invalidResponse(String)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let message):
            return message
        case .unknownProvider(let provider):
            return "Unknown LLM provider: \(provider)"
        case .requestFailed(let message):
            return "LLM request failed: \(message)"
        case .invalidResponse(let message):
            return "Invalid LLM response: \(message)"
        case .decodingFailed(let message):
            return "Failed to decode LLM response: \(message)"
        }
    }
}
