import Foundation

/// A part of a section page. A section shows only the pockets its template
/// declares, always in this one global order, so every page reads the same way.
/// Raw values are part of the `.dosar` contract.
public enum SectionPocket: String, Codable, CaseIterable, Sendable, Comparable {
    /// What comes up next (at most `upcomingLimit` items).
    case upcoming
    /// Tenancies filed under a property.
    case tenants
    /// Products filed under a home or listed in the Garanții box.
    case products
    /// Subscriptions filed under an asset or listed in the Abonamente box.
    case subscriptions
    /// Documents (Acte).
    case documents
    /// What happened: visits, repairs, purchases (Istoric).
    case history
    /// People and firms (Oameni).
    case people
    /// What it cost (Bani).
    case money
    /// Key facts and free label–value rows (Date importante).
    case keyFacts

    /// Most items the Urmează pocket shows; the rest are in the Urmează tab.
    public static let upcomingLimit = 3

    public var title: String {
        switch self {
        case .upcoming: return String(localized: "Urmează", comment: "Section pocket")
        case .tenants: return String(localized: "Chiriași", comment: "Section pocket")
        case .products: return String(localized: "Produse", comment: "Section pocket")
        case .subscriptions: return String(localized: "Abonamente", comment: "Section pocket")
        case .documents: return String(localized: "Acte", comment: "Section pocket")
        case .history: return String(localized: "Istoric", comment: "Section pocket")
        case .people: return String(localized: "Oameni", comment: "Section pocket")
        case .money: return String(localized: "Bani", comment: "Section pocket")
        case .keyFacts: return String(localized: "Date importante", comment: "Section pocket")
        }
    }

    private var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    public static func < (lhs: SectionPocket, rhs: SectionPocket) -> Bool { lhs.order < rhs.order }

    /// The given pockets in the global order, without duplicates.
    public static func ordered<S: Sequence>(_ pockets: S) -> [SectionPocket] where S.Element == SectionPocket {
        Array(Set(pockets)).sorted()
    }

    /// What a page of an asset shows when nothing else is said.
    public static let standard: [SectionPocket] = [.upcoming, .documents, .history, .people, .money, .keyFacts]
}

/// A free label and value the person adds under Date importante, such as
/// "Cod alarmă poartă" or "Număr contract apă".
public struct CustomFact: Hashable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var label: String
    public var value: String
    /// Hidden behind the section lock and left out of search.
    public var isSensitive: Bool
    /// A code (an alarm, a gate, a Wi-Fi password) kept like a PIN: `value` holds
    /// only sealed text, shown masked and opened after a fresh Face ID
    /// (`SecretFields`). It never leaves the phone.
    public var isSecret: Bool

    public init(id: UUID = UUID(), label: String, value: String, isSensitive: Bool = false, isSecret: Bool = false) {
        self.id = id
        self.label = label
        self.value = value
        self.isSensitive = isSensitive || isSecret
        self.isSecret = isSecret
    }

    private enum CodingKeys: String, CodingKey { case id, label, value, isSensitive, isSecret }

    /// Words that name a code rather than a fact: a row labelled with one starts
    /// as a secret. Not "cod" alone: a client or POD code is an ordinary identifier.
    static let codeWords = ["parola", "pin", "puk", "wifi", "wi-fi", "alarma", "interfon", "poarta", "seif", "acces"]

    /// Whether a label names a code (an alarm code, a Wi-Fi password), so the row
    /// is offered as a secret. Ignores case and diacritics.
    public static func looksLikeCode(_ label: String) -> Bool {
        let words = label.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ro"))
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" })
            .map(String.init)
        return words.contains { word in codeWords.contains { word == $0 || (word.hasPrefix($0) && $0.count >= 4) } }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: (try c.decodeIfPresent(String.self, forKey: .id)).flatMap(UUID.init(uuidString:)) ?? UUID(),
            label: try c.decode(String.self, forKey: .label),
            value: try c.decode(String.self, forKey: .value),
            isSensitive: try c.decodeIfPresent(Bool.self, forKey: .isSensitive) ?? false,
            isSecret: try c.decodeIfPresent(Bool.self, forKey: .isSecret) ?? false
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id.uuidString.lowercased(), forKey: .id)
        try c.encode(label, forKey: .label)
        try c.encode(value, forKey: .value)
        if isSensitive { try c.encode(true, forKey: .isSensitive) }
        if isSecret { try c.encode(true, forKey: .isSecret) }
    }
}
