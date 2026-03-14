import Foundation

// MARK: - Errors

enum AIClientError: Error, LocalizedError {
    case invalidResponse
    case unauthorized
    case rateLimited
    case serverError(Int)
    case httpError(Int, Data)
    case emptyResponse
    case notConfigured
    case encodingFailed
    case requestTimeout(Int)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from AI API"
        case .unauthorized: return "API key is invalid or expired (401/403)"
        case .rateLimited: return "API rate limit exceeded (429)"
        case .serverError(let code): return "Server error (\(code))"
        case .httpError(let code, _): return "HTTP error (\(code))"
        case .emptyResponse: return "AI returned an empty response"
        case .notConfigured: return "AI model is not configured"
        case .encodingFailed: return "Failed to encode request"
        case .requestTimeout(let ms): return "Request timeout (\(ms / 1000)s)"
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        }
    }
}

extension AIClientError {
    /// Whether this error should trigger fallback to the next provider.
    var shouldFallback: Bool {
        switch self {
        case .rateLimited:    return true
        case .serverError:    return true
        case .networkError:   return true
        case .requestTimeout: return true
        case .unauthorized:   return true
        case .invalidResponse, .emptyResponse: return false
        case .notConfigured, .encodingFailed:  return false
        case .httpError(let code, _): return code >= 500
        }
    }
}

// MARK: - Request/Response Models (OpenAI Compatible)

struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [Message]
    let temperature: Double
    let responseFormat: ResponseFormat?

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case responseFormat = "response_format"
    }

    struct Message: Encodable {
        let role: String
        let content: [Content]

        struct Content: Encodable {
            let type: String
            let text: String?
            let imageUrl: ImageURL?

            enum CodingKeys: String, CodingKey {
                case type, text
                case imageUrl = "image_url"
            }

            static func text(_ text: String) -> Content {
                Content(type: "text", text: text, imageUrl: nil)
            }

            static func image(base64: String, mimeType: String = "image/jpeg") -> Content {
                Content(
                    type: "image_url",
                    text: nil,
                    imageUrl: ImageURL(url: "data:\(mimeType);base64,\(base64)")
                )
            }
        }

        struct ImageURL: Encodable {
            let url: String
        }
    }

    struct ResponseFormat: Encodable {
        let type: String

        static let json = ResponseFormat(type: "json_object")
    }
}

struct ChatCompletionResponse: Decodable {
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Decodable {
        let message: Message

        struct Message: Decodable {
            let content: String?
        }
    }

    struct Usage: Decodable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

// MARK: - AI Client

final class AIClient: Sendable {
    static let shared = AIClient()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 600
        config.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: config)
    }

    /// Generic chat completion call (OpenAI compatible)
    func chatCompletion(
        config: AIModelSlot,
        request: ChatCompletionRequest,
        debugFunction: String = "unknown"
    ) async throws -> ChatCompletionResponse {
        guard config.isConfigured else {
            throw AIClientError.notConfigured
        }

        let endpoint = Self.buildEndpointURL(config.endpoint)

        guard let url = URL(string: endpoint) else {
            throw AIClientError.invalidResponse
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        for (key, value) in config.customHeaders {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        urlRequest.httpBody = try JSONEncoder().encode(request)

        // Live tracking
        let debugLog = DebugLogger.shared
        let trackingID = debugLog.trackRequestStart(
            function: debugFunction,
            model: config.modelName,
            endpoint: config.endpoint,
            messages: request.messages
        )

        let startTime = CFAbsoluteTimeGetCurrent()

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            let wrappedError: AIClientError
            if let urlError = error as? URLError, urlError.code == .timedOut {
                wrappedError = .requestTimeout(durationMs)
            } else {
                wrappedError = .networkError(error)
            }
            debugLog.logLLMCall(function: debugFunction, model: config.modelName, endpoint: config.endpoint, request: request, response: nil, error: wrappedError, durationMs: durationMs)
            debugLog.trackRequestError(id: trackingID, durationMs: durationMs, error: wrappedError)
            throw wrappedError
        }

        let durationMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

        guard let httpResponse = response as? HTTPURLResponse else {
            let err = AIClientError.invalidResponse
            debugLog.trackRequestError(id: trackingID, durationMs: durationMs, error: err)
            throw err
        }

        switch httpResponse.statusCode {
        case 200:
            do {
                let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
                debugLog.logLLMCall(
                    function: debugFunction,
                    model: config.modelName,
                    endpoint: config.endpoint,
                    request: request,
                    response: decoded,
                    error: nil,
                    durationMs: durationMs
                )
                debugLog.trackRequestComplete(id: trackingID, durationMs: durationMs, response: decoded)
                return decoded
            } catch is DecodingError {
                let err = AIClientError.invalidResponse
                debugLog.trackRequestError(id: trackingID, durationMs: durationMs, error: err)
                throw err
            }
        case 401, 403:
            let err = AIClientError.unauthorized
            debugLog.logLLMCall(function: debugFunction, model: config.modelName, endpoint: config.endpoint, request: request, response: nil, error: err, durationMs: durationMs)
            debugLog.trackRequestError(id: trackingID, durationMs: durationMs, error: err)
            throw err
        case 429:
            let err = AIClientError.rateLimited
            debugLog.logLLMCall(function: debugFunction, model: config.modelName, endpoint: config.endpoint, request: request, response: nil, error: err, durationMs: durationMs)
            debugLog.trackRequestError(id: trackingID, durationMs: durationMs, error: err)
            throw err
        case 500...599:
            let err = AIClientError.serverError(httpResponse.statusCode)
            debugLog.logLLMCall(function: debugFunction, model: config.modelName, endpoint: config.endpoint, request: request, response: nil, error: err, durationMs: durationMs)
            debugLog.trackRequestError(id: trackingID, durationMs: durationMs, error: err)
            throw err
        default:
            let err = AIClientError.httpError(httpResponse.statusCode, data)
            debugLog.logLLMCall(function: debugFunction, model: config.modelName, endpoint: config.endpoint, request: request, response: nil, error: err, durationMs: durationMs)
            debugLog.trackRequestError(id: trackingID, durationMs: durationMs, error: err)
            throw err
        }
    }

    /// Screenshot analysis convenience method
    func analyzeScreenshot(
        imageBase64: String,
        config: AIModelSlot
    ) async throws -> ScreenshotAnalysis {
        let request = ChatCompletionRequest(
            model: config.modelName,
            messages: [
                .init(role: "system", content: [.text(ScreenshotAnalysisPrompt.systemPrompt())]),
                .init(role: "user", content: [.image(base64: imageBase64)])
            ],
            temperature: config.temperature,
            responseFormat: .json
        )

        let response = try await chatCompletion(config: config, request: request, debugFunction: "screenshot_analysis")

        guard let content = response.choices.first?.message.content else {
            throw AIClientError.emptyResponse
        }

        guard let jsonData = content.data(using: .utf8) else {
            throw AIClientError.emptyResponse
        }

        do {
            return try JSONDecoder().decode(ScreenshotAnalysis.self, from: jsonData)
        } catch is DecodingError {
            throw AIClientError.invalidResponse
        }
    }

    /// Test connection to verify API configuration.
    /// Automatically detects embedding models and uses the correct endpoint.
    func testConnection(config: AIModelSlot) async throws -> Bool {
        if Self.isEmbeddingModel(config.modelName) {
            let result = try await getEmbedding("test", config: config)
            return !result.isEmpty
        } else {
            let request = ChatCompletionRequest(
                model: config.modelName,
                messages: [
                    .init(role: "user", content: [.text("Reply with exactly: OK")])
                ],
                temperature: 0,
                responseFormat: nil
            )
            let response = try await chatCompletion(config: config, request: request, debugFunction: "test_connection")
            return response.choices.first?.message.content != nil
        }
    }

    // MARK: - Embedding

    /// Request body for the OpenAI-compatible embeddings endpoint.
    private struct EmbeddingRequest: Encodable {
        let model: String
        let input: String
    }

    /// Response from the embeddings endpoint.
    private struct EmbeddingResponse: Decodable {
        let data: [EmbeddingData]
        struct EmbeddingData: Decodable {
            let embedding: [Float]
        }
    }

    /// Get embedding vector for a text string.
    func getEmbedding(_ text: String, config: AIModelSlot) async throws -> [Float] {
        guard config.isConfigured else {
            throw AIClientError.notConfigured
        }

        let endpoint = Self.buildEmbeddingURL(config.endpoint)
        guard let url = URL(string: endpoint) else {
            throw AIClientError.invalidResponse
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        for (key, value) in config.customHeaders {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        let body = EmbeddingRequest(model: config.modelName, input: text)
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            if let urlError = error as? URLError, urlError.code == .timedOut {
                throw AIClientError.requestTimeout(0)
            }
            throw AIClientError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let decoded = try JSONDecoder().decode(EmbeddingResponse.self, from: data)
            guard let first = decoded.data.first else { throw AIClientError.emptyResponse }
            return first.embedding
        case 401, 403:
            throw AIClientError.unauthorized
        case 429:
            throw AIClientError.rateLimited
        case 500...599:
            throw AIClientError.serverError(httpResponse.statusCode)
        default:
            throw AIClientError.httpError(httpResponse.statusCode, data)
        }
    }

    /// Heuristic: model name containing "embedding" indicates an embedding model.
    static func isEmbeddingModel(_ modelName: String) -> Bool {
        modelName.localizedCaseInsensitiveContains("embedding")
    }

    // MARK: - URL Construction

    /// Build the full chat completions URL from user-provided endpoint.
    static func buildEndpointURL(_ base: String) -> String {
        let url = Self.normalizeBase(base)
        if url.hasSuffix("/chat/completions") { return url }
        if url.hasSuffix("/v1") { return url + "/chat/completions" }
        return url + "/v1/chat/completions"
    }

    /// Embedding endpoint: use the user-provided URL as-is (no path appending).
    /// Embedding APIs vary across providers, so the user specifies the full URL.
    static func buildEmbeddingURL(_ base: String) -> String {
        Self.normalizeBase(base)
    }

    private static func normalizeBase(_ base: String) -> String {
        base.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
    }
}
