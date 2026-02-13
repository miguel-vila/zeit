import Foundation

/// OpenAI API client for cloud model inference
final class OpenAIClient: LLMProvider, @unchecked Sendable {
    let model: String
    let apiKey: String
    let baseURL: URL

    init(
        model: String,
        apiKey: String,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!
    ) {
        self.model = model
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    // MARK: - LLMProvider

    func generate(
        prompt: String,
        temperature: Double? = nil,
        jsonMode: Bool = false
    ) async throws -> String {
        let url = baseURL.appendingPathComponent("chat/completions")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120

        let body = ChatRequest(
            model: model,
            messages: [Message(role: "user", content: prompt)],
            temperature: temperature,
            responseFormat: jsonMode ? ResponseFormat(type: "json_object") : nil
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.requestFailed("Invalid response type")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.requestFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let chatResponse = try decoder.decode(ChatResponse.self, from: data)

        guard let content = chatResponse.choices.first?.message.content else {
            throw LLMError.invalidResponse("No content in response")
        }

        return content
    }

    // MARK: - Request/Response Models

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
        let temperature: Double?
        let responseFormat: ResponseFormat?

        enum CodingKeys: String, CodingKey {
            case model, messages, temperature
            case responseFormat = "response_format"
        }
    }

    private struct Message: Codable {
        let role: String
        let content: String
    }

    private struct ResponseFormat: Encodable {
        let type: String
    }

    private struct ChatResponse: Decodable {
        let id: String
        let choices: [Choice]
        let usage: Usage?

        struct Choice: Decodable {
            let index: Int
            let message: Message
            let finishReason: String?
        }

        struct Usage: Decodable {
            let promptTokens: Int
            let completionTokens: Int
            let totalTokens: Int
        }
    }
}
