import Foundation

// One small adapter per provider: how to ask for a document's fields as JSON, how to
// find the JSON in the answer, how to test a key, and what each error status means.
// Keys travel only in headers, never in a URL. Nothing here knows what the fields mean.

/// What every provider is asked: the instructions, the fields as a JSON Schema, and the
/// page as a JPEG.
public struct CloudReadingRequest: Sendable {
    public let instructions: String
    public let schema: JSONValue
    /// A short identifier for the schema, where the provider wants one.
    public let schemaName: String
    public let jpeg: Data

    public init(instructions: String, schema: JSONValue, schemaName: String = "document_fields", jpeg: Data) {
        self.instructions = instructions
        self.schema = schema
        self.schemaName = schemaName
        self.jpeg = jpeg
    }
}

/// One provider's request and response shapes.
public protocol AIProviderAdapter: Sendable {
    /// The request that reads a page into JSON matching the schema.
    func readingRequest(_ request: CloudReadingRequest, config: AIProviderConfig) throws -> URLRequest
    /// The JSON object the provider answered with.
    func answer(from data: Data) throws -> JSONValue
    /// A request that costs nothing and tells whether the key and model work.
    func keyTestRequest(config: AIProviderConfig) throws -> URLRequest
    /// A request that lists the models this key can use. Costs nothing.
    func modelsRequest(config: AIProviderConfig) throws -> URLRequest
    /// The models in the provider's answer, before the shared filter.
    func models(from data: Data) throws -> [AIModel]
    /// What an error status means, from the status and the provider's error body.
    func error(status: Int, body: Data) -> AIProviderError
}

extension AIProvider {
    /// The adapter for this provider.
    public var adapter: any AIProviderAdapter {
        switch self {
        case .gemini: GeminiAdapter()
        case .openAI: OpenAIAdapter()
        case .anthropic: AnthropicAdapter()
        case .openAICompatible: OpenAICompatibleAdapter()
        }
    }
}

// MARK: - Sending

/// Sends a provider's requests and turns every failure into an `AIProviderError`.
/// `send` is injectable, so tests use canned responses and never the network.
public struct AIClient: Sendable {
    public typealias Send = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    let send: Send

    public init(send: @escaping Send = { request in try await URLSession.shared.data(for: request) }) {
        self.send = send
    }

    /// Reads a page with the configured provider.
    public func read(_ request: CloudReadingRequest, config: AIProviderConfig) async throws -> JSONValue {
        let adapter = config.provider.adapter
        let data = try await perform(try adapter.readingRequest(request, config: config), adapter: adapter)
        return try adapter.answer(from: data)
    }

    /// Tests a key with a request that reads nothing.
    public func testKey(config: AIProviderConfig) async -> AIKeyStatus {
        if config.provider.requiresKey, config.key?.isEmpty ?? true { return .empty }
        let adapter = config.provider.adapter
        do {
            _ = try await perform(try adapter.keyTestRequest(config: config), adapter: adapter)
            return .valid
        } catch {
            return .failed(AIProviderError(transport: error))
        }
    }

    /// The models this key can use for reading documents, newest first. Models that
    /// can't read a page (speech, embeddings, image or video generation) are left out.
    public func listModels(config: AIProviderConfig) async throws -> [AIModel] {
        if config.provider.requiresKey, config.key?.isEmpty ?? true { throw AIProviderError.notConfigured }
        let adapter = config.provider.adapter
        let data = try await perform(try adapter.modelsRequest(config: config), adapter: adapter)
        return AIModel.forReading(try adapter.models(from: data))
    }

    private func perform(_ request: URLRequest, adapter: any AIProviderAdapter) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await send(request)
        } catch {
            throw AIProviderError(transport: error)
        }
        guard let http = response as? HTTPURLResponse else { throw AIProviderError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let error = adapter.error(status: http.statusCode, body: data)
            CaptureLog.engine.error("AI provider answered \(http.statusCode): \(error.code, privacy: .public)")
            throw error
        }
        return data
    }
}

// MARK: - Shared pieces

enum AIHTTP {
    static func request(_ url: URL, method: String = "POST", headers: [String: String], body: JSONValue?, timeout: TimeInterval) throws -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            request.httpBody = try encoder.encode(body)
        }
        return request
    }

    /// Reading a photo can take a while on a thinking model.
    static let readingTimeout: TimeInterval = 120
    static let testTimeout: TimeInterval = 10

    /// The JSON object inside a model's text answer, tolerating a Markdown fence.
    static func object(inText text: String) throws -> JSONValue {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            trimmed = trimmed.drop { $0 != "\n" }.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasSuffix("```") { trimmed = String(trimmed.dropLast(3)) }
        }
        guard let data = trimmed.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data), value.object != nil else {
            throw AIProviderError.badResponse
        }
        return value
    }

    static func decode(_ data: Data) throws -> JSONValue {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { throw AIProviderError.badResponse }
        return value
    }

    /// The mapping most providers share.
    static func commonError(status: Int) -> AIProviderError {
        switch status {
        case 401, 403: .invalidKey
        case 402: .quota
        case 404: .modelUnavailable
        case 408: .offline
        case 429: .quota
        case 500...599: .busy
        default: .badResponse
        }
    }

    static func base64(_ data: Data) -> String { data.base64EncodedString() }
}

// MARK: - Google Gemini

/// Gemini's `generateContent` with structured output (`generationConfig.responseFormat`).
public struct GeminiAdapter: AIProviderAdapter {
    static let base = "https://generativelanguage.googleapis.com/v1beta/models/"

    public init() {}

    private func modelURL(_ config: AIProviderConfig, suffix: String = "") throws -> URL {
        let model = config.model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? config.model
        guard let url = URL(string: Self.base + model + suffix) else { throw AIProviderError.modelUnavailable }
        return url
    }

    public func readingRequest(_ request: CloudReadingRequest, config: AIProviderConfig) throws -> URLRequest {
        let body: JSONValue = .object([
            "contents": .array([.object([
                "role": "user",
                "parts": .array([
                    .object(["text": .string(request.instructions)]),
                    .object(["inlineData": .object(["mimeType": "image/jpeg", "data": .string(AIHTTP.base64(request.jpeg))])]),
                ]),
            ])]),
            "generationConfig": .object([
                "responseFormat": .object(["text": .object(["mimeType": "APPLICATION_JSON", "schema": request.schema])]),
                "thinkingConfig": .object(["thinkingLevel": "LOW"]),
            ]),
        ])
        return try AIHTTP.request(try modelURL(config, suffix: ":generateContent"), headers: ["x-goog-api-key": config.key ?? ""],
                                  body: body, timeout: AIHTTP.readingTimeout)
    }

    public func answer(from data: Data) throws -> JSONValue {
        let response = try AIHTTP.decode(data)
        if response["promptFeedback"]?["blockReason"]?.string != nil { throw AIProviderError.refused }
        guard let candidate = response["candidates"]?[0] else { throw AIProviderError.badResponse }
        if ["SAFETY", "PROHIBITED_CONTENT", "SPII", "RECITATION"].contains(candidate["finishReason"]?.string ?? "") {
            throw AIProviderError.refused
        }
        let parts = candidate["content"]?["parts"]?.array ?? []
        // Thought summaries, when present, come before the answer.
        guard let text = parts.last(where: { $0["thought"]?.bool != true && $0["text"]?.string != nil })?["text"]?.string else {
            throw AIProviderError.badResponse
        }
        return try AIHTTP.object(inText: text)
    }

    public func keyTestRequest(config: AIProviderConfig) throws -> URLRequest {
        try AIHTTP.request(try modelURL(config), method: "GET", headers: ["x-goog-api-key": config.key ?? ""], body: nil, timeout: AIHTTP.testTimeout)
    }

    public func modelsRequest(config: AIProviderConfig) throws -> URLRequest {
        guard let url = URL(string: String(Self.base.dropLast()) + "?pageSize=1000") else { throw AIProviderError.badResponse }
        return try AIHTTP.request(url, method: "GET", headers: ["x-goog-api-key": config.key ?? ""], body: nil, timeout: AIHTTP.testTimeout)
    }

    /// `models[]` with `name` ("models/…") and the methods each supports; only
    /// models that can `generateContent` can read a page.
    public func models(from data: Data) throws -> [AIModel] {
        guard let list = try AIHTTP.decode(data)["models"]?.array else { throw AIProviderError.badResponse }
        return list.compactMap { entry in
            guard let name = entry["name"]?.string,
                  (entry["supportedGenerationMethods"]?.array ?? []).contains(.string("generateContent")) else { return nil }
            let id = name.hasPrefix("models/") ? String(name.dropFirst("models/".count)) : name
            return AIModel(id: id, displayName: entry["displayName"]?.string)
        }
    }

    public func error(status: Int, body: Data) -> AIProviderError {
        let error = (try? AIHTTP.decode(body))?["error"]
        let reasons = (error?["details"]?.array ?? []).compactMap { $0["reason"]?.string }
        if reasons.contains("API_KEY_INVALID") || reasons.contains("API_KEY_EXPIRED") { return .invalidKey }
        if error?["status"]?.string == "RESOURCE_EXHAUSTED" { return .quota }
        if error?["status"]?.string == "NOT_FOUND" { return .modelUnavailable }
        return AIHTTP.commonError(status: status)
    }
}

// MARK: - OpenAI

/// OpenAI's Responses API with a strict JSON Schema (`text.format`).
public struct OpenAIAdapter: AIProviderAdapter {
    static let base = "https://api.openai.com/v1"

    public init() {}

    private func headers(_ config: AIProviderConfig) -> [String: String] {
        ["Authorization": "Bearer \(config.key ?? "")"]
    }

    public func readingRequest(_ request: CloudReadingRequest, config: AIProviderConfig) throws -> URLRequest {
        guard let url = URL(string: Self.base + "/responses") else { throw AIProviderError.badResponse }
        let body: JSONValue = .object([
            "model": .string(config.model),
            "input": .array([.object([
                "role": "user",
                "content": .array([
                    .object(["type": "input_text", "text": .string(request.instructions)]),
                    .object(["type": "input_image", "image_url": .string("data:image/jpeg;base64," + AIHTTP.base64(request.jpeg)), "detail": "high"]),
                ]),
            ])]),
            "text": .object(["format": .object([
                "type": "json_schema", "name": .string(request.schemaName), "schema": request.schema, "strict": true,
            ])]),
            "store": false,
        ])
        return try AIHTTP.request(url, headers: headers(config), body: body, timeout: AIHTTP.readingTimeout)
    }

    public func answer(from data: Data) throws -> JSONValue {
        let response = try AIHTTP.decode(data)
        let parts = (response["output"]?.array ?? [])
            .filter { $0["type"]?.string == "message" }
            .flatMap { $0["content"]?.array ?? [] }
        if parts.contains(where: { $0["type"]?.string == "refusal" }) { throw AIProviderError.refused }
        guard let text = parts.first(where: { $0["type"]?.string == "output_text" })?["text"]?.string else {
            throw AIProviderError.badResponse
        }
        return try AIHTTP.object(inText: text)
    }

    public func keyTestRequest(config: AIProviderConfig) throws -> URLRequest {
        let model = config.model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? config.model
        guard let url = URL(string: Self.base + "/models/" + model) else { throw AIProviderError.modelUnavailable }
        return try AIHTTP.request(url, method: "GET", headers: headers(config), body: nil, timeout: AIHTTP.testTimeout)
    }

    public func modelsRequest(config: AIProviderConfig) throws -> URLRequest {
        guard let url = URL(string: Self.base + "/models") else { throw AIProviderError.badResponse }
        return try AIHTTP.request(url, method: "GET", headers: headers(config), body: nil, timeout: AIHTTP.testTimeout)
    }

    public func models(from data: Data) throws -> [AIModel] {
        try Self.modelList(data)
    }

    /// `data[]` with `id` and `created` (seconds), as OpenAI and compatible services list them.
    static func modelList(_ data: Data) throws -> [AIModel] {
        guard let list = try AIHTTP.decode(data)["data"]?.array else { throw AIProviderError.badResponse }
        return list.compactMap { entry in
            guard let id = entry["id"]?.string else { return nil }
            return AIModel(id: id, created: entry["created"]?.double.map { Date(timeIntervalSince1970: $0) })
        }
    }

    public func error(status: Int, body: Data) -> AIProviderError {
        OpenAIAdapter.chatError(status: status, body: body)
    }

    /// Shared with OpenAI-compatible services, which answer errors the same way.
    static func chatError(status: Int, body: Data) -> AIProviderError {
        let code = (try? AIHTTP.decode(body))?["error"]?["code"]?.string
        switch code {
        case "invalid_api_key": return .invalidKey
        case "insufficient_quota", "rate_limit_exceeded": return .quota
        case "model_not_found": return .modelUnavailable
        default: return AIHTTP.commonError(status: status)
        }
    }
}

// MARK: - Anthropic Claude

/// Anthropic's Messages API with an image block and structured output (`output_config.format`).
public struct AnthropicAdapter: AIProviderAdapter {
    static let base = "https://api.anthropic.com/v1"
    static let version = "2026-10-21"
    /// Models that accept the server-side fallback when a safety check declines a request.
    static let fallbackBeta = "server-side-fallback-2026-07-01"

    public init() {}

    private func headers(_ config: AIProviderConfig, fallback: Bool = false) -> [String: String] {
        var headers = ["x-api-key": config.key ?? "", "anthropic-version": Self.version]
        if fallback { headers["anthropic-beta"] = Self.fallbackBeta }
        return headers
    }

    static func acceptsFallback(_ model: String) -> Bool {
        model.hasPrefix("claude-opus-5") || model.hasPrefix("claude-fable-5") || model == "claude-sonnet-5-5"
    }

    public func readingRequest(_ request: CloudReadingRequest, config: AIProviderConfig) throws -> URLRequest {
        guard let url = URL(string: Self.base + "/messages") else { throw AIProviderError.badResponse }
        let fallback = Self.acceptsFallback(config.model)
        var body: [String: JSONValue] = [
            "model": .string(config.model),
            "max_tokens": .int(16_000),
            "messages": .array([.object([
                "role": "user",
                "content": .array([
                    .object(["type": "image", "source": .object(["type": "base64", "media_type": "image/jpeg", "data": .string(AIHTTP.base64(request.jpeg))])]),
                    .object(["type": "text", "text": .string(request.instructions)]),
                ]),
            ])]),
            "output_config": .object(["format": .object(["type": "json_schema", "schema": request.schema])]),
        ]
        if fallback { body["fallbacks"] = "default" }
        return try AIHTTP.request(url, headers: headers(config, fallback: fallback), body: .object(body), timeout: AIHTTP.readingTimeout)
    }

    public func answer(from data: Data) throws -> JSONValue {
        let response = try AIHTTP.decode(data)
        if response["stop_reason"]?.string == "refusal" { throw AIProviderError.refused }
        let texts = (response["content"]?.array ?? []).filter { $0["type"]?.string == "text" }.compactMap { $0["text"]?.string }
        guard let text = texts.last else { throw AIProviderError.badResponse }
        return try AIHTTP.object(inText: text)
    }

    public func keyTestRequest(config: AIProviderConfig) throws -> URLRequest {
        let model = config.model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? config.model
        guard let url = URL(string: Self.base + "/models/" + model) else { throw AIProviderError.modelUnavailable }
        return try AIHTTP.request(url, method: "GET", headers: headers(config), body: nil, timeout: AIHTTP.testTimeout)
    }

    public func modelsRequest(config: AIProviderConfig) throws -> URLRequest {
        guard let url = URL(string: Self.base + "/models?limit=1000") else { throw AIProviderError.badResponse }
        return try AIHTTP.request(url, method: "GET", headers: headers(config), body: nil, timeout: AIHTTP.testTimeout)
    }

    /// `data[]` with `id`, `display_name` and `created_at`. Every Claude model reads images.
    public func models(from data: Data) throws -> [AIModel] {
        guard let list = try AIHTTP.decode(data)["data"]?.array else { throw AIProviderError.badResponse }
        let dates = ISO8601DateFormatter()
        return list.compactMap { entry in
            guard let id = entry["id"]?.string else { return nil }
            return AIModel(id: id, displayName: entry["display_name"]?.string, created: entry["created_at"]?.string.flatMap { dates.date(from: $0) })
        }
    }

    public func error(status: Int, body: Data) -> AIProviderError {
        switch (try? AIHTTP.decode(body))?["error"]?["type"]?.string {
        case "authentication_error", "permission_error": return .invalidKey
        case "billing_error", "rate_limit_error": return .quota
        case "not_found_error": return .modelUnavailable
        case "overloaded_error", "api_error": return .busy
        default: return AIHTTP.commonError(status: status)
        }
    }
}

// MARK: - OpenAI-compatible

/// Chat Completions at the address the person gives, with `response_format` set to a
/// JSON Schema. The schema is also in the instructions, for servers that don't enforce it.
public struct OpenAICompatibleAdapter: AIProviderAdapter {
    public init() {}

    private func url(_ config: AIProviderConfig, _ path: String) throws -> URL {
        guard let base = config.baseURL, let url = URL(string: base.absoluteString + path) else { throw AIProviderError.notConfigured }
        return url
    }

    private func headers(_ config: AIProviderConfig) -> [String: String] {
        guard let key = config.key, !key.isEmpty else { return [:] }
        return ["Authorization": "Bearer \(key)"]
    }

    public func readingRequest(_ request: CloudReadingRequest, config: AIProviderConfig) throws -> URLRequest {
        let schemaText = String(data: (try? JSONEncoder().encode(request.schema)) ?? Data(), encoding: .utf8) ?? ""
        let body: JSONValue = .object([
            "model": .string(config.model),
            "messages": .array([.object([
                "role": "user",
                "content": .array([
                    .object(["type": "text", "text": .string(request.instructions + "\n\nAnswer with one JSON object matching this JSON Schema:\n" + schemaText)]),
                    .object(["type": "image_url", "image_url": .object(["url": .string("data:image/jpeg;base64," + AIHTTP.base64(request.jpeg))])]),
                ]),
            ])]),
            "response_format": .object([
                "type": "json_schema",
                "json_schema": .object(["name": .string(request.schemaName), "schema": request.schema, "strict": true]),
            ]),
        ])
        return try AIHTTP.request(try url(config, "/chat/completions"), headers: headers(config), body: body, timeout: AIHTTP.readingTimeout)
    }

    public func answer(from data: Data) throws -> JSONValue {
        let message = try AIHTTP.decode(data)["choices"]?[0]?["message"]
        if let refusal = message?["refusal"]?.string, !refusal.isEmpty { throw AIProviderError.refused }
        guard let text = message?["content"]?.string else { throw AIProviderError.badResponse }
        return try AIHTTP.object(inText: text)
    }

    public func keyTestRequest(config: AIProviderConfig) throws -> URLRequest {
        try AIHTTP.request(try url(config, "/models"), method: "GET", headers: headers(config), body: nil, timeout: AIHTTP.testTimeout)
    }

    public func error(status: Int, body: Data) -> AIProviderError {
        OpenAIAdapter.chatError(status: status, body: body)
    }

    public func modelsRequest(config: AIProviderConfig) throws -> URLRequest {
        try AIHTTP.request(try url(config, "/models"), method: "GET", headers: headers(config), body: nil, timeout: AIHTTP.testTimeout)
    }

    public func models(from data: Data) throws -> [AIModel] {
        try OpenAIAdapter.modelList(data)
    }
}

// MARK: - JSON

/// A JSON value, for building request bodies and schemas and reading answers without
/// a type per provider.
public enum JSONValue: Hashable, Sendable, Codable, ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    case string(String)
    case int(Int)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(stringLiteral value: String) { self = .string(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int.self) { self = .int(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public subscript(key: String) -> JSONValue? { object?[key] }
    public subscript(index: Int) -> JSONValue? {
        guard let array, array.indices.contains(index) else { return nil }
        return array[index]
    }

    public var object: [String: JSONValue]? { if case .object(let value) = self { value } else { nil } }
    public var array: [JSONValue]? { if case .array(let value) = self { value } else { nil } }
    public var bool: Bool? { if case .bool(let value) = self { value } else { nil } }
    public var string: String? { if case .string(let value) = self { value } else { nil } }
    /// A JSON number, whole or not. Text is never read as a number here: an answer's
    /// numbers are read by `ModelQuestions.number(_:as:)`, through the one number reader.
    public var double: Double? {
        switch self {
        case .int(let whole): Double(whole)
        case .number(let value): value
        default: nil
        }
    }
}
