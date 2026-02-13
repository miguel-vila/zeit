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
}

/// Protocol for vision-capable LLM providers
protocol VisionLLMProvider: Sendable {
    /// Generate a response for the given prompt with images
    /// - Parameters:
    ///   - prompt: The prompt to send to the model
    ///   - images: Base64-encoded images to include
    ///   - temperature: Optional temperature for response randomness
    ///   - jsonMode: Whether to request JSON-formatted output
    /// - Returns: The generated text response
    func generateWithVision(
        prompt: String,
        images: [String],
        temperature: Double?,
        jsonMode: Bool
    ) async throws -> String
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

    /// Create a vision-capable LLM provider
    /// - Parameter model: Vision model config name
    /// - Returns: A vision LLM provider instance
    static func createVision(model: String) throws -> VisionLLMProvider {
        guard let mlxClient = MLXClient(configName: model) else {
            throw LLMError.unknownProvider("MLX vision model not found: \(model)")
        }
        return mlxClient
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
