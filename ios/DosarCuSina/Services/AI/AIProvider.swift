import Foundation

// The optional cloud reading: the person brings their own key for one of several
// providers. Everything here is configuration and wording; each provider's request
// and response live in its adapter (`AIProviderAdapters.swift`), and what the answers
// mean (grounding, checks) is shared by all of them (`CloudCaptureExtractor`).

/// A service that can read a document photo with the person's own key.
public enum AIProvider: String, CaseIterable, Sendable, Codable, Identifiable {
    case gemini
    case openAI
    case anthropic
    /// Any service that speaks OpenAI's chat format at an address the person gives:
    /// OpenRouter, Mistral, LM Studio or Ollama on the home network, and others.
    case openAICompatible

    public var id: String { rawValue }

    /// The name people know the service by, for sentences ("…se trimite la Google Gemini").
    public var name: String {
        switch self {
        case .gemini: "Google Gemini"
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic Claude"
        case .openAICompatible: String(localized: "serviciul ales", comment: "The custom OpenAI-compatible AI service, inside a sentence.")
        }
    }

    /// The name in a picker.
    public var pickerName: String {
        switch self {
        case .openAICompatible: String(localized: "Compatibil OpenAI", comment: "AI provider: any OpenAI-compatible service at a custom address.")
        default: name
        }
    }

    /// The short name for a button ("Citește mai bine cu Gemini").
    public var shortName: String {
        switch self {
        case .gemini: "Gemini"
        case .openAI: "OpenAI"
        case .anthropic: "Claude"
        case .openAICompatible: String(localized: "modelul tău", comment: "Button: read better with your own AI model.")
        }
    }

    /// The model used unless the person picks another. Checked against each provider's
    /// documentation; one place to change when a model is retired.
    public var defaultModel: String {
        switch self {
        case .gemini: "gemini-3.8-flash"
        case .openAI: "gpt-6-astra"
        case .anthropic: "claude-opus-5-5"
        case .openAICompatible: ""
        }
    }

    /// Where the person gets a key.
    public var keyPageURL: URL? {
        switch self {
        case .gemini: URL(string: "https://aistudio.google.com/app/apikey")
        case .openAI: URL(string: "https://platform.openai.com/api-keys")
        case .anthropic: URL(string: "https://platform.claude.com/settings/keys")
        case .openAICompatible: nil
        }
    }

    /// The provider's own words on how it uses what is sent with an API key. Linked, not
    /// summarised, so the app never claims more than the provider does.
    public var dataPolicyURL: URL? {
        switch self {
        case .gemini: URL(string: "https://ai.google.dev/gemini-api/terms")
        case .openAI: URL(string: "https://developers.openai.com/api/docs/guides/your-data")
        case .anthropic: URL(string: "https://www.anthropic.com/legal/commercial-terms")
        case .openAICompatible: nil
        }
    }

    /// Local servers (LM Studio, Ollama) often need no key.
    public var requiresKey: Bool { self != .openAICompatible }

    /// The Keychain account each provider's key is kept under. Gemini keeps the account
    /// keys were saved under before there were several providers.
    var keychainAccount: String {
        switch self {
        case .gemini: "gemini_api_key"
        case .openAI: "openai_api_key"
        case .anthropic: "anthropic_api_key"
        case .openAICompatible: "openai_compatible_api_key"
        }
    }
}

/// Everything one request needs: who, which model, with which key, and where.
public struct AIProviderConfig: Sendable, Equatable {
    public let provider: AIProvider
    public let model: String
    public let key: String?
    /// Only for `openAICompatible`: the service's address, ending before `/chat/completions`.
    public let baseURL: URL?

    public init(provider: AIProvider, model: String, key: String?, baseURL: URL? = nil) {
        self.provider = provider
        self.model = model
        self.key = key
        self.baseURL = baseURL
    }
}

/// The one place the cloud reading is configured: the chosen provider, a model per
/// provider (its default unless the person typed another), the compatible service's
/// address, and each provider's key in the Keychain.
public struct AIProviderSettings: Sendable {

    /// The defaults suite the choices are kept in; nil for the app's standard defaults.
    let suiteName: String?
    let keys: any AIKeyStoring

    public static var standard: AIProviderSettings { AIProviderSettings(suiteName: nil, keys: KeychainManager.Keys()) }

    init(suiteName: String?, keys: any AIKeyStoring) {
        self.suiteName = suiteName
        self.keys = keys
    }

    private var defaults: UserDefaults { suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard }

    private static let providerKey = "ai.provider"
    private static func modelKey(_ provider: AIProvider) -> String { "ai.model.\(provider.rawValue)" }
    private static let baseURLKey = "ai.openAICompatible.baseURL"

    /// The provider the person chose; Gemini until they choose another.
    public var provider: AIProvider {
        get { defaults.string(forKey: Self.providerKey).flatMap(AIProvider.init(rawValue:)) ?? .gemini }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.providerKey) }
    }

    /// The model the person typed for a provider, empty when they use its default.
    public func customModel(for provider: AIProvider) -> String {
        defaults.string(forKey: Self.modelKey(provider)) ?? ""
    }

    public func setCustomModel(_ model: String, for provider: AIProvider) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { defaults.removeObject(forKey: Self.modelKey(provider)) } else { defaults.set(trimmed, forKey: Self.modelKey(provider)) }
    }

    /// The model a request uses.
    public func model(for provider: AIProvider) -> String {
        let custom = customModel(for: provider)
        return custom.isEmpty ? provider.defaultModel : custom
    }

    /// The compatible service's address as the person typed it.
    public var baseURLText: String {
        get { defaults.string(forKey: Self.baseURLKey) ?? "" }
        nonmutating set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.baseURLKey) }
    }

    public func key(for provider: AIProvider) -> String? { keys.key(for: provider) }

    @discardableResult
    public func saveKey(_ key: String, for provider: AIProvider) -> Bool { keys.save(key, for: provider) }

    public func deleteKey(for provider: AIProvider) { keys.delete(for: provider) }

    /// A provider's configuration, or nil while something it needs is missing.
    public func config(for provider: AIProvider) -> AIProviderConfig? {
        let model = model(for: provider)
        guard !model.isEmpty else { return nil }
        let key = key(for: provider)
        if provider.requiresKey, key == nil { return nil }
        if provider == .openAICompatible {
            guard let url = Self.validatedBaseURL(baseURLText) else { return nil }
            return AIProviderConfig(provider: provider, model: model, key: key, baseURL: url)
        }
        return AIProviderConfig(provider: provider, model: model, key: key)
    }

    /// The chosen provider's configuration, when it is ready to use.
    public var current: AIProviderConfig? { config(for: provider) }

    /// Whether the person set up a provider. Without one, reading stays on the phone.
    public var isReady: Bool { current != nil }

    /// An address keys may be sent to: `https`, or `http` only to a server on the home
    /// network (LM Studio, Ollama), never to the internet in the clear.
    public static func validatedBaseURL(_ text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(), !host.isEmpty,
              url.query == nil, url.user == nil else { return nil }
        switch scheme {
        case "https": return url
        case "http": return isLocal(host) ? url : nil
        default: return nil
        }
    }

    /// `localhost`, `.local` names and private IPv4 addresses.
    static func isLocal(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".local") || host == "127.0.0.1" { return true }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        switch (parts[0], parts[1]) {
        case (10, _), (192, 168): return true
        case (172, let second): return (16...31).contains(second)
        default: return false
        }
    }
}

/// Where keys are kept. The Keychain in the app; a dictionary in tests.
public protocol AIKeyStoring: Sendable {
    func key(for provider: AIProvider) -> String?
    func save(_ key: String, for provider: AIProvider) -> Bool
    func delete(for provider: AIProvider)
}

// MARK: - Errors and wording

/// Why a cloud reading or a key test didn't work, told apart so the person knows what to do.
public enum AIProviderError: Error, Equatable, Sendable, CaseIterable {
    /// No provider set up, or its key is missing.
    case notConfigured
    /// No internet, or the service couldn't be reached.
    case offline
    /// The service refused the key.
    case invalidKey
    /// The key used up its requests or credit for now.
    case quota
    /// The model doesn't exist or isn't available to this key.
    case modelUnavailable
    /// The service is busy or failing for now.
    case busy
    /// The service declined to read the document.
    case refused
    /// An answer the app couldn't use.
    case badResponse

    /// A stable code for notices and logs.
    public var code: String {
        switch self {
        case .notConfigured: "noKey"
        case .offline: "offline"
        case .invalidKey: "invalidKey"
        case .quota: "quota"
        case .modelUnavailable: "modelUnavailable"
        case .busy: "busy"
        case .refused: "refused"
        case .badResponse: "badResponse"
        }
    }

    public init(code: String) {
        self = Self.allCases.first { $0.code == code } ?? .badResponse
    }

    /// From an error thrown before any answer came back.
    public init(transport error: any Error) {
        let offline: Set<URLError.Code> = [
            .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
            .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed,
        ]
        if let urlError = error as? URLError, offline.contains(urlError.code) {
            self = .offline
        } else if let known = error as? AIProviderError {
            self = known
        } else {
            self = .badResponse
        }
    }

    /// What happened and what to do, in plain words.
    public func message(provider: AIProvider) -> String {
        switch self {
        case .notConfigured:
            String(localized: "Nu ai adăugat o cheie. Citirea de pe telefon merge oricum.", comment: "Cloud reading: no key set up.")
        case .offline:
            String(localized: "Nu ești conectat la internet. Citirea de pe telefon merge în continuare.", comment: "Cloud reading: offline.")
        case .invalidKey:
            String(localized: "\(provider.name) nu a acceptat cheia. Verifică în Setări dacă ai copiat-o întreagă.", comment: "Cloud reading: the key was refused. The argument is the provider.")
        case .quota:
            String(localized: "Cheia și-a terminat cererile pentru acum. Încearcă mai târziu sau verifică planul la \(provider.name).", comment: "Cloud reading: quota used up.")
        case .modelUnavailable:
            String(localized: "Modelul ales nu e disponibil pentru cheia ta. Alege altul în Setări.", comment: "Cloud reading: the model isn't available.")
        case .busy:
            String(localized: "\(provider.name) e ocupat acum. Încearcă din nou peste câteva minute.", comment: "Cloud reading: the service is busy.")
        case .refused:
            String(localized: "\(provider.name) nu a citit actul. Valorile citite pe telefon rămân.", comment: "Cloud reading: the service declined.")
        case .badResponse:
            String(localized: "\(provider.name) nu a răspuns cum trebuie. Încearcă din nou peste câteva minute.", comment: "Cloud reading: unexpected answer.")
        }
    }
}

/// The outcome of testing a key.
public enum AIKeyStatus: Sendable, Equatable {
    case valid
    /// Nothing was typed.
    case empty
    case failed(AIProviderError)
}
