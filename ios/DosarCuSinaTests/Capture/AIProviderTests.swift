import CoreGraphics
import Foundation
import Testing
@testable import DosarCuSina

/// The AI provider layer: each adapter's request, answer and errors against canned JSON,
/// and the shared schema, grounding and checks. No test touches the network. Keys and
/// data are placeholders.
@Suite("AI providers")
struct AIProviderTests {

    let today = CaptureDay(year: 2026, month: 11, day: 2)!
    static let placeholderKey = "placeholder-not-a-key"

    private func config(_ provider: AIProvider, base: String? = nil) -> AIProviderConfig {
        AIProviderConfig(provider: provider, model: provider == .openAICompatible ? "local-vision" : provider.defaultModel,
                         key: Self.placeholderKey, baseURL: base.flatMap(URL.init(string:)))
    }

    private func reading(_ kind: CaptureDocumentKind = .passport) -> CloudReadingRequest {
        let schema = CloudSchema(kind: kind)
        return CloudReadingRequest(instructions: schema.instructions, schema: schema.json, jpeg: Data([0xFF, 0xD8, 0xFF]))
    }

    private func body(_ request: URLRequest) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: try #require(request.httpBody))
    }

    private func data(_ json: String) -> Data { Data(json.utf8) }

    // MARK: Requests

    @Test("Every provider sends the key in a header, never in the address")
    func keysInHeaders() throws {
        let cases: [(AIProvider, String)] = [(.gemini, "x-goog-api-key"), (.openAI, "Authorization"), (.anthropic, "x-api-key"), (.openAICompatible, "Authorization")]
        for (provider, header) in cases {
            let configured = config(provider, base: "https://ai.exemplu.ro/v1")
            for request in [try provider.adapter.readingRequest(reading(), config: configured), try provider.adapter.keyTestRequest(config: configured)] {
                let url = try #require(request.url?.absoluteString)
                #expect(!url.contains(Self.placeholderKey), "\(provider)")
                #expect(request.url?.query == nil, "\(provider)")
                #expect(request.value(forHTTPHeaderField: header)?.contains(Self.placeholderKey) == true, "\(provider)")
            }
        }
    }

    @Test("Gemini: the current model, the image inline and the schema as structured output")
    func geminiRequest() throws {
        let request = try GeminiAdapter().readingRequest(reading(), config: config(.gemini))
        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent")
        let json = try body(request)
        let parts = try #require(json["contents"]?[0]?["parts"]?.array)
        #expect(parts.contains { $0["inlineData"]?["mimeType"]?.string == "image/jpeg" })
        #expect(json["generationConfig"]?["responseFormat"]?["text"]?["mimeType"]?.string == "APPLICATION_JSON")
        #expect(json["generationConfig"]?["responseFormat"]?["text"]?["schema"]?["properties"]?["expiryDate"] != nil)
    }

    @Test("OpenAI: the Responses API with a strict JSON Schema and the image as a data address")
    func openAIRequest() throws {
        let request = try OpenAIAdapter().readingRequest(reading(), config: config(.openAI))
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.placeholderKey)")
        let json = try body(request)
        #expect(json["model"]?.string == "gpt-6-astra")
        #expect(json["text"]?["format"]?["type"]?.string == "json_schema")
        #expect(json["text"]?["format"]?["strict"]?.bool == true)
        let content = try #require(json["input"]?[0]?["content"]?.array)
        #expect(content.contains { $0["type"]?.string == "input_image" && $0["image_url"]?.string?.hasPrefix("data:image/jpeg;base64,") == true })
    }

    @Test("Anthropic: the Messages API with an image block and output_config.format")
    func anthropicRequest() throws {
        let request = try AnthropicAdapter().readingRequest(reading(), config: config(.anthropic))
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == AnthropicAdapter.version)
        let json = try body(request)
        #expect(json["model"]?.string == "claude-opus-5-5")
        #expect(json["output_config"]?["format"]?["type"]?.string == "json_schema")
        let content = try #require(json["messages"]?[0]?["content"]?.array)
        #expect(content.first?["type"]?.string == "image")
        #expect(content.first?["source"]?["media_type"]?.string == "image/jpeg")
    }

    @Test("Compatible: chat completions at the given address, with the schema also in the words")
    func compatibleRequest() throws {
        let configured = config(.openAICompatible, base: "http://192.168.1.20:1234/v1")
        let request = try OpenAICompatibleAdapter().readingRequest(reading(.utilityInvoice), config: configured)
        #expect(request.url?.absoluteString == "http://192.168.1.20:1234/v1/chat/completions")
        let json = try body(request)
        #expect(json["response_format"]?["json_schema"]?["schema"]?["properties"]?["dueDate"] != nil)
        let text = json["messages"]?[0]?["content"]?[0]?["text"]?.string ?? ""
        #expect(text.contains("dueDate"))
        // No key, no header: local servers often need none.
        let keyless = AIProviderConfig(provider: .openAICompatible, model: "local-vision", key: nil, baseURL: configured.baseURL)
        #expect(try OpenAICompatibleAdapter().readingRequest(reading(), config: keyless).value(forHTTPHeaderField: "Authorization") == nil)
    }

    // MARK: Answers

    @Test("Each provider's answer is unwrapped to the same JSON object")
    func answers() throws {
        let object = #"{\"surname\":\"EXEMPLU\"}"#
        let gemini = data(#"{"candidates":[{"content":{"role":"model","parts":[{"text":""# + object + #""}]},"finishReason":"STOP"}]}"#)
        let openAI = data(#"{"output":[{"type":"reasoning"},{"type":"message","content":[{"type":"output_text","text":""# + object + #""}]}]}"#)
        let anthropic = data(#"{"stop_reason":"end_turn","content":[{"type":"thinking","thinking":""},{"type":"text","text":""# + object + #""}]}"#)
        let compatible = data(#"{"choices":[{"message":{"role":"assistant","content":"```json\n"# + object + #"\n```"}}]}"#)
        for (adapter, payload) in [(GeminiAdapter() as any AIProviderAdapter, gemini), (OpenAIAdapter(), openAI), (AnthropicAdapter(), anthropic), (OpenAICompatibleAdapter(), compatible)] {
            #expect(try adapter.answer(from: payload)["surname"]?.string == "EXEMPLU")
        }
    }

    @Test("A provider that declines says so")
    func refusals() {
        #expect(throws: AIProviderError.refused) { try GeminiAdapter().answer(from: data(#"{"promptFeedback":{"blockReason":"SAFETY"}}"#)) }
        #expect(throws: AIProviderError.refused) { try OpenAIAdapter().answer(from: data(#"{"output":[{"type":"message","content":[{"type":"refusal","refusal":"no"}]}]}"#)) }
        #expect(throws: AIProviderError.refused) { try AnthropicAdapter().answer(from: data(#"{"stop_reason":"refusal","content":[]}"#)) }
        #expect(throws: AIProviderError.badResponse) { try OpenAICompatibleAdapter().answer(from: data(#"{"choices":[{"message":{"content":"not json"}}]}"#)) }
    }

    @Test("Errors tell offline, a bad key, the quota and a missing model apart")
    func errors() {
        let gemini = GeminiAdapter()
        #expect(gemini.error(status: 400, body: data(#"{"error":{"code":400,"status":"INVALID_ARGUMENT","details":[{"reason":"API_KEY_INVALID"}]}}"#)) == .invalidKey)
        #expect(gemini.error(status: 429, body: data(#"{"error":{"code":429,"status":"RESOURCE_EXHAUSTED"}}"#)) == .quota)
        #expect(gemini.error(status: 404, body: data(#"{"error":{"code":404,"status":"NOT_FOUND"}}"#)) == .modelUnavailable)
        #expect(gemini.error(status: 400, body: data(#"{"error":{"code":400,"status":"INVALID_ARGUMENT"}}"#)) == .badResponse)

        let openAI = OpenAIAdapter()
        #expect(openAI.error(status: 401, body: data(#"{"error":{"code":"invalid_api_key"}}"#)) == .invalidKey)
        #expect(openAI.error(status: 429, body: data(#"{"error":{"code":"insufficient_quota"}}"#)) == .quota)
        #expect(openAI.error(status: 404, body: data(#"{"error":{"code":"model_not_found"}}"#)) == .modelUnavailable)

        let anthropic = AnthropicAdapter()
        #expect(anthropic.error(status: 401, body: data(#"{"type":"error","error":{"type":"authentication_error"}}"#)) == .invalidKey)
        #expect(anthropic.error(status: 429, body: data(#"{"type":"error","error":{"type":"rate_limit_error"}}"#)) == .quota)
        #expect(anthropic.error(status: 404, body: data(#"{"type":"error","error":{"type":"not_found_error"}}"#)) == .modelUnavailable)
        #expect(anthropic.error(status: 529, body: data(#"{"type":"error","error":{"type":"overloaded_error"}}"#)) == .busy)

        #expect(OpenAICompatibleAdapter().error(status: 503, body: Data()) == .busy)
        #expect(AIProviderError(transport: URLError(.notConnectedToInternet)) == .offline)
    }

    @Test("Every error has its own plain message")
    func messages() {
        let messages = AIProviderError.allCases.map { $0.message(provider: .anthropic) }
        #expect(Set(messages).count == messages.count)
        #expect(messages.allSatisfy { !$0.contains("!") })
        #expect(AIProviderError.invalidKey.message(provider: .anthropic).contains("Anthropic Claude"))
    }

    // MARK: Sending

    @Test("The client turns transport failures and statuses into provider errors")
    func client() async throws {
        let offline = AIClient { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: AIProviderError.offline) { try await offline.read(reading(), config: config(.gemini)) }

        let limited = AIClient { request in
            (Data(#"{"error":{"code":429,"status":"RESOURCE_EXHAUSTED"}}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!)
        }
        await #expect(throws: AIProviderError.quota) { try await limited.read(reading(), config: config(.gemini)) }
        #expect(await limited.testKey(config: config(.gemini)) == .failed(.quota))

        let fine = AIClient { request in (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!) }
        #expect(await fine.testKey(config: config(.openAI)) == .valid)
        #expect(await fine.testKey(config: AIProviderConfig(provider: .openAI, model: "gpt-6-astra", key: nil)) == .empty)
    }

    // MARK: Configuration

    final class MemoryKeys: AIKeyStoring, @unchecked Sendable {
        private var keys: [AIProvider: String] = [:]
        private let lock = NSLock()
        func key(for provider: AIProvider) -> String? { lock.withLock { keys[provider] } }
        func save(_ key: String, for provider: AIProvider) -> Bool { lock.withLock { keys[provider] = key }; return true }
        func delete(for provider: AIProvider) { lock.withLock { keys[provider] = nil } }
    }

    static func settings() -> AIProviderSettings {
        let suite = "test.ai.\(UUID().uuidString)"
        return AIProviderSettings(suiteName: suite, keys: MemoryKeys())
    }

    @Test("One configuration place: a provider, a model per provider, a key per provider")
    func configuration() {
        let settings = Self.settings()
        #expect(settings.provider == .gemini)
        #expect(!settings.isReady)
        settings.saveKey(Self.placeholderKey, for: .gemini)
        #expect(settings.current?.model == "gemini-3.8-flash")
        settings.setCustomModel("gemini-3.6-flash", for: .gemini)
        #expect(settings.current?.model == "gemini-3.6-flash")
        settings.setCustomModel("  ", for: .gemini)
        #expect(settings.current?.model == "gemini-3.8-flash")

        settings.provider = .anthropic
        #expect(!settings.isReady)  // Keys are kept per provider.

        settings.provider = .openAICompatible
        #expect(!settings.isReady)
        settings.baseURLText = "https://ai.exemplu.ro/v1/"
        settings.setCustomModel("local-vision", for: .openAICompatible)
        #expect(settings.current?.baseURL?.absoluteString == "https://ai.exemplu.ro/v1")
        #expect(settings.current?.key == nil)
    }

    @Test("Keys go only to https, or to http on the home network")
    func baseURLs() {
        #expect(AIProviderSettings.validatedBaseURL("https://openrouter.ai/api/v1") != nil)
        #expect(AIProviderSettings.validatedBaseURL("http://192.168.1.20:1234/v1") != nil)
        #expect(AIProviderSettings.validatedBaseURL("http://localhost:11434/v1") != nil)
        #expect(AIProviderSettings.validatedBaseURL("http://server.local:1234/v1") != nil)
        #expect(AIProviderSettings.validatedBaseURL("http://ai.exemplu.ro/v1") == nil)
        #expect(AIProviderSettings.validatedBaseURL("http://172.32.0.1/v1") == nil)
        #expect(AIProviderSettings.validatedBaseURL("https://ai.exemplu.ro/v1?key=x") == nil)
        #expect(AIProviderSettings.validatedBaseURL("ftp://ai.exemplu.ro") == nil)
    }

    // MARK: The schema

    @Test("The provider is asked what the document is and every field any kind carries, the phone's guess first")
    func schemas() {
        let passport = CloudSchema(kind: .passport)
        let names = Set(passport.fields.map(\.name))
        #expect(names.isSuperset(of: ["surname", "givenNames", "documentNumber", "birthDate", "expiryDate", "issueDate", "personalNumber", "machineReadableZone"]))
        #expect(names.isSuperset(of: ["policyNumber", "total", "podCode", "vin"]), "A wrong guess never hides another kind's fields")
        #expect(passport.json["required"]?.array?.count == passport.fields.count + 1)
        #expect(passport.json["required"]?.array?.first?.string == ModelQuestions.kindName)
        #expect(passport.json["properties"]?[ModelQuestions.kindName]?["enum"]?.array?.count == CaptureDocumentKind.allCases.count)
        #expect(!passport.instructions.contains("passport"), "The phone's guess isn't told to the provider")
        #expect(passport.json["additionalProperties"]?.bool == false)
        #expect(passport.fields.first { $0.name == "expiryDate" }?.description.contains("date of expiry") == true)

        let olderCard = CloudSchema(kind: .identityCard)
        #expect(olderCard.fields.contains { $0.name == "issueDate" })

        let invoice = CloudSchema(kind: .utilityInvoice)
        #expect(Array(invoice.fields.compactMap(\.key).prefix(CaptureDocumentKind.utilityInvoice.expectedKeys.count)) == CaptureDocumentKind.utilityInvoice.expectedKeys)
        #expect(Set(CloudSchema(kind: .rcaPolicy).fields.map(\.name)) == Set(invoice.fields.map(\.name)), "Every guess asks the same fields")
        #expect(invoice.fields.first { $0.key == .total }?.format == .money)
    }

    // MARK: Grounding and checks

    private func map(_ json: String, kind: CaptureDocumentKind = .passport, text: String = "") throws -> [CaptureFieldKey: CaptureField] {
        let answer = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let fields = ModelAnswerMapper.fields(from: answer, asked: CloudSchema(kind: kind).questions, recognizedText: text, today: today, resolver: CatalogComponentResolver())
        return Dictionary(fields.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    @Test("A checked zone from the answer gives certain values")
    func zoneFromAnswer() throws {
        let lines = MRZFixtures.passport().components(separatedBy: "\n").map { "\"\($0)\"" }.joined(separator: ",")
        let fields = try map(#"{"surname":"EXEMPLU","expiryDate":"2031-04-13","machineReadableZone":["# + lines + "]}")
        #expect(fields[.expiryDate]?.value.day == CaptureDay(year: 2031, month: 4, day: 12))
        #expect(fields[.expiryDate]?.tier == .cloudModel)
        #expect(fields[.expiryDate]?.needsCheck == false)
        #expect(fields[.documentNumber]?.value.text == "X04512378")
    }

    @Test("Values in the recognized text, or passing their own check, are kept; the rest are candidates")
    func grounding() throws {
        let text = "PAȘAPORT\nNume / Surname\nEXEMPLU\nCNP 1800101990006"
        let fields = try map(#"{"surname":"EXEMPLU","givenNames":"MARIA","personalNumber":"1800101990006","expiryDate":"2031-04-12","issueDate":"1990-01-01"}"#, text: text)
        #expect(fields[.surname]?.needsCheck == false)              // in the text
        #expect(fields[.givenNames]?.needsCheck == true)            // only the model saw it
        #expect(fields[.personalNumber]?.confidence == ModelAnswerMapper.checked)
        #expect(fields[.expiryDate]?.needsCheck == false)           // inside its window
        #expect(fields[.issueDate]?.needsCheck == true)             // outside: a candidate at most
        #expect(fields[.holderName]?.value.text == "MARIA EXEMPLU")

        let wrongCNP = try map(#"{"personalNumber":"1800101990007"}"#)
        #expect(wrongCNP[.personalNumber]?.needsCheck == true)
    }

    @Test("Invoices: printed amounts and identifiers are kept, invented ones are candidates; a VIN passes by its check digit")
    func invoiceGrounding() throws {
        let text = "ENGIE Romania S.A.\nFactura nr. EXM 0012345\nTotal de plată 348,50 lei"
        let fields = try map(#"{"provider":"ENGIE Romania S.A.","invoiceNumber":"EXM 0012345","total":{"amount":348.5,"currency":"RON"},"dueDate":"2026-11-20","clientCode":"999999"}"#,
                             kind: .utilityInvoice, text: text)
        #expect(fields[.provider]?.needsCheck == false)
        #expect(fields[.invoiceNumber]?.needsCheck == false)
        #expect(fields[.total]?.value.money?.amount == Decimal(string: "348.5"))
        #expect(fields[.total]?.needsCheck == false)
        #expect(fields[.dueDate]?.needsCheck == true)
        #expect(fields[.clientCode]?.needsCheck == true)

        let vin = try map(#"{"vin":"1M8GDM9AXKP042788"}"#, kind: .itpReport)
        #expect(vin[.vin]?.confidence == ModelAnswerMapper.checked)
    }

    @Test("Through the engine: a canned Gemini answer is merged, never above a checked value, with no network")
    func throughEngine() async throws {
        let settings = Self.settings()
        settings.saveKey(Self.placeholderKey, for: .gemini)
        let answer = #"{"surname":"EXEMPLU","givenNames":"ANA","documentNumber":"X99999999","expiryDate":"2033-01-01","machineReadableZone":[]}"#
        let escaped = answer.replacingOccurrences(of: "\"", with: "\\\"")
        let client = AIClient { request in
            #expect(request.url?.host == "generativelanguage.googleapis.com")
            let body = #"{"candidates":[{"content":{"parts":[{"text":""# + escaped + #""}]},"finishReason":"STOP"}]}"#
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let cloud = CloudCaptureExtractor(settings: settings, client: client)
        let text = "PAȘAPORT\n" + MRZFixtures.passport()
        let engine = CaptureEngine(analyzer: CaptureAnalyzer(), recognizer: CaptureEngineTests.FixedRecognizer(text: text),
                                   normalizer: nil, onDeviceModel: nil, cloudModel: cloud, store: nil)
        let result = try await engine.capture(CaptureRequest(.images([CaptureImage(image: CaptureDocumentStoreTests.page(width: 500, height: 350))]),
                                                             options: CaptureOptions(useCloudModel: true, referenceDate: Date(timeIntervalSince1970: 1_793_577_600))))
        // The zone read on the phone, checked by its digits, stays.
        #expect(result.field(.documentNumber)?.value.text == "X04512378")
        #expect(result.field(.expiryDate)?.value.day == CaptureDay(year: 2031, month: 4, day: 12))
        #expect(result.field(.givenNames)?.value.text == "ANA")
        #expect(!result.notices.contains { if case .cloudModelFailed = $0 { true } else { false } })
    }

    @Test("Through the engine: a failed reading says why")
    func engineFailure() async throws {
        let settings = Self.settings()
        settings.saveKey(Self.placeholderKey, for: .openAI)
        settings.provider = .openAI
        let client = AIClient { request in
            (Data(#"{"error":{"code":"invalid_api_key"}}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
        }
        let engine = CaptureEngine(analyzer: CaptureAnalyzer(), recognizer: CaptureEngineTests.FixedRecognizer(text: "Factura"),
                                   normalizer: nil, onDeviceModel: nil, cloudModel: CloudCaptureExtractor(settings: settings, client: client), store: nil)
        let result = try await engine.capture(CaptureRequest(.images([CaptureImage(image: CaptureDocumentStoreTests.page(width: 300, height: 400))]),
                                                             options: CaptureOptions(useCloudModel: true)))
        #expect(result.notices.contains(.cloudModelFailed(reason: AIProviderError.invalidKey.code)))
    }
}
