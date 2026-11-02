import Foundation

/// A part or job a template knows about, such as front brake pads on a car or
/// the boiler in a home. Line items point at it by `key`, so the history can
/// answer "when did I last change it" whatever the bill called it.
public struct ComponentDefinition: Hashable, Sendable, Codable, Identifiable {
    /// Stable key, unique within the template, such as `brakes.padsFront`.
    public var key: String
    public var name: String
    /// A heading to group components under, such as "Frâne".
    public var group: String
    /// Other ways people write it on bills and in notes (matched without diacritics or case).
    public var synonyms: [String]

    public var id: String { key }

    public init(key: String, name: String, group: String, synonyms: [String] = []) {
        self.key = key
        self.name = name
        self.group = group
        self.synonyms = synonyms
    }

    private enum CodingKeys: String, CodingKey { case key, name, group, synonyms }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        name = try c.decode(String.self, forKey: .name)
        group = try c.decodeIfPresent(String.self, forKey: .group) ?? ""
        synonyms = try c.decodeIfPresent([String].self, forKey: .synonyms) ?? []
    }
}

/// Matching free text to a template's components.
public enum ComponentCatalog {
    public static let customKeyPrefix = "custom."

    /// The component whose name or synonym appears in `text`, preferring the longest match
    /// ("plăcuțe frână spate" picks the rear pads, not just "plăcuțe").
    public static func match(_ text: String, in components: [ComponentDefinition]) -> ComponentDefinition? {
        let haystack = SearchText.normalize(text)
        guard !haystack.isEmpty else { return nil }
        var best: (component: ComponentDefinition, length: Int)?
        for component in components {
            for phrase in [component.name] + component.synonyms {
                let needle = SearchText.normalize(phrase)
                guard !needle.isEmpty, SearchText.containsPhrase(haystack, needle) else { continue }
                if needle.count > (best?.length ?? 0) {
                    best = (component, needle.count)
                }
            }
        }
        return best?.component
    }

    /// The catalog key for `text`, or a stable `custom.<slug>` key for anything the catalog doesn't know.
    public static func key(for text: String, in components: [ComponentDefinition]) -> String {
        if let match = match(text, in: components) { return match.key }
        let slug = SearchText.normalize(text).split(separator: " ").joined(separator: "-")
        return customKeyPrefix + (slug.isEmpty ? "item" : slug)
    }
}

/// Text normalization shared by search and component matching: lowercase,
/// no diacritics (so "polita" finds "poliță"), letters and digits only.
public enum SearchText {
    public static func normalize(_ text: String) -> String {
        let folded = text
            .replacingOccurrences(of: "ş", with: "ș").replacingOccurrences(of: "ţ", with: "ț")
            .replacingOccurrences(of: "Ş", with: "Ș").replacingOccurrences(of: "Ţ", with: "Ț")
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "ro_RO"))
        let words = folded.split { !$0.isLetter && !$0.isNumber }
        return words.joined(separator: " ")
    }

    public static func tokens(_ text: String) -> [String] {
        normalize(text).split(separator: " ").map(String.init)
    }

    /// Whether the words of the normalized `phrase` appear in order in the normalized
    /// `text`, each as the start of a word, so Romanian endings still match
    /// ("ulei" finds "uleiul", "disc" finds "discurile").
    public static func containsPhrase(_ text: String, _ phrase: String) -> Bool {
        let words = text.split(separator: " ")
        let needle = phrase.split(separator: " ")
        guard !needle.isEmpty, needle.count <= words.count else { return false }
        for start in 0...(words.count - needle.count) {
            if zip(words[start...], needle).allSatisfy({ $0.hasPrefix($1) }) { return true }
        }
        return false
    }
}
