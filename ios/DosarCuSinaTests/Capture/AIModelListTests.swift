import Foundation
import Testing
@testable import DosarCuSina

/// Listing the models a key can use, for the picker in Settings. Canned answers only.
@Suite("AI model list")
struct AIModelListTests {

    private func client(_ body: String, check: (@Sendable (URLRequest) -> Void)? = nil) -> AIClient {
        AIClient { request in
            check?(request)
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    @Test func geminiListsOnlyModelsThatCanReadAPage() async throws {
        let body = #"""
        {"models":[
          {"name":"models/gemini-3.8-flash","displayName":"Gemini 3.8 Flash","supportedGenerationMethods":["generateContent","countTokens"]},
          {"name":"models/gemini-3.8-pro","displayName":"Gemini 3.8 Pro","supportedGenerationMethods":["generateContent"]},
          {"name":"models/gemini-embedding-002","supportedGenerationMethods":["embedContent"]},
          {"name":"models/imagen-5","supportedGenerationMethods":["generateContent"]}
        ]}
        """#
        let config = AIProviderConfig(provider: .gemini, model: "", key: "test-key")
        let models = try await client(body) { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.absoluteString.hasPrefix("https://generativelanguage.googleapis.com/v1beta/models?") == true)
            #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "test-key")
            #expect(request.url?.query?.contains("key=") == false, "The key never goes in the address")
        }.listModels(config: config)
        #expect(models.map(\.id) == ["gemini-3.8-pro", "gemini-3.8-flash"])
        #expect(models.last?.displayName == "Gemini 3.8 Flash")
    }

    @Test func openAIDropsSpeechEmbeddingsAndImageModelsNewestFirst() async throws {
        let body = #"""
        {"data":[
          {"id":"gpt-6-astra","created":1790000000},
          {"id":"gpt-5.5","created":1760000000},
          {"id":"text-embedding-4","created":1795000000},
          {"id":"gpt-6-realtime","created":1795000000},
          {"id":"whisper-2","created":1700000000}
        ]}
        """#
        let models = try await client(body).listModels(config: AIProviderConfig(provider: .openAI, model: "", key: "k"))
        #expect(models.map(\.id) == ["gpt-6-astra", "gpt-5.5"])
    }

    @Test func claudeListsItsModelsWithTheirNames() async throws {
        let body = #"""
        {"data":[
          {"id":"claude-sonnet-5-5","display_name":"Claude Sonnet 5.5","created_at":"2026-08-01T00:00:00Z","type":"model"},
          {"id":"claude-opus-5-5","display_name":"Claude Opus 5.5","created_at":"2026-09-01T00:00:00Z","type":"model"}
        ],"has_more":false}
        """#
        let models = try await client(body) { request in
            #expect(request.value(forHTTPHeaderField: "x-api-key") == "k")
            #expect(request.value(forHTTPHeaderField: "anthropic-version") != nil)
        }.listModels(config: AIProviderConfig(provider: .anthropic, model: "", key: "k"))
        #expect(models.map(\.id) == ["claude-opus-5-5", "claude-sonnet-5-5"])
        #expect(models.first?.displayName == "Claude Opus 5.5")
    }

    @Test func aCompatibleServiceIsAskedAtItsOwnAddress() async throws {
        let config = AIProviderConfig(provider: .openAICompatible, model: "", key: nil, baseURL: URL(string: "http://192.168.1.20:1234/v1"))
        let models = try await client(#"{"data":[{"id":"qwen-vl-9b"}]}"#) { request in
            #expect(request.url?.absoluteString == "http://192.168.1.20:1234/v1/models")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil, "No key, no header")
        }.listModels(config: config)
        #expect(models.map(\.id) == ["qwen-vl-9b"])
    }

    @Test func withoutAKeyNothingIsAsked() async {
        await #expect(throws: AIProviderError.notConfigured) {
            _ = try await client("{}").listModels(config: AIProviderConfig(provider: .gemini, model: "", key: nil))
        }
    }

    @Test func modelsCanBeListedBeforeOneIsChosen() {
        let settings = AIProviderTests.settings()
        settings.baseURLText = "https://ai.exemplu.ro/v1"
        #expect(settings.config(for: .openAICompatible) == nil, "Not ready to read without a model")
        #expect(settings.connection(for: .openAICompatible) != nil, "But its models can be listed")
        #expect(settings.connection(for: .gemini) == nil, "Gemini needs a key first")
    }
}
