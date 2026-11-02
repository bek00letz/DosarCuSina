import Foundation

/// A model a provider offers to a key, for the model picker in Settings.
public struct AIModel: Hashable, Sendable, Identifiable {
    /// What requests name it by, such as "gemini-3.8-flash".
    public let id: String
    /// The provider's friendly name, when it gives one.
    public let displayName: String?
    /// When the provider published it, when it says; newer models are listed first.
    public let created: Date?

    public init(id: String, displayName: String? = nil, created: Date? = nil) {
        self.id = id
        self.displayName = displayName
        self.created = created
    }

    /// Words in a model's id that mean it can't read a page: speech, embeddings,
    /// moderation, and image, video or music generation. One list for every provider.
    static let notForReading = [
        "embed", "tts", "whisper", "transcribe", "audio", "speech", "realtime", "moderation",
        "dall-e", "imagen", "veo", "lyria", "image-generation", "aqa", "search",
    ]

    /// The models that can read a document, newest first, then by name; each once.
    static func forReading(_ models: [AIModel]) -> [AIModel] {
        var seen: Set<String> = []
        return models
            .filter { model in
                let id = model.id.lowercased()
                return !notForReading.contains { id.contains($0) } && seen.insert(model.id).inserted
            }
            .sorted { lhs, rhs in
                switch (lhs.created, rhs.created) {
                case let (left?, right?) where left != right: return left > right
                case (_?, nil): return true
                case (nil, _?): return false
                default: return lhs.id.localizedStandardCompare(rhs.id) == .orderedDescending
                }
            }
    }
}
