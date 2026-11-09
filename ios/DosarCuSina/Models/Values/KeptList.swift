import Foundation

/// A list stored as JSON that a newer build may have written: the entries this build can
/// read, and the ones it can't, kept raw in their places and written back unchanged. A
/// template's sections, deadlines and parts, and a section's rows under Date importante.
///
/// It is the rule `FieldValues` follows for values: keep what can't be read, raw, and never
/// write back less than was stored. An entry this build can't read goes only when one it
/// can read takes its place (the same key or id), so editing the readable ones never loses
/// the others. Reading code sees `items` (or the list itself, a collection of them).
public struct KeptList<Element: Codable & Hashable & Sendable & Identifiable>: Hashable, Sendable, Codable, RandomAccessCollection, MutableCollection, ExpressibleByArrayLiteral {
    /// The entries this build reads, in order.
    public var items: [Element]
    /// The entries it can't, raw, each with its place in the list as it was read.
    public private(set) var unreadable: [Unreadable]

    public struct Unreadable: Hashable, Sendable {
        /// Its place among all the entries, readable or not, when it was read.
        public let position: Int
        public let raw: JSONValue

        /// The key or id it is known by, when it has one this build can read.
        var identity: String? {
            (raw["key"]?.string ?? raw["id"]?.string)?.lowercased()
        }
    }

    public init(_ items: [Element] = []) {
        self.items = items
        self.unreadable = []
    }

    public init(arrayLiteral elements: Element...) {
        self.init(elements)
    }

    private init(items: [Element], unreadable: [Unreadable]) {
        self.items = items
        self.unreadable = unreadable
    }

    /// Whether every entry could be read.
    public var isFullyRead: Bool { unreadable.isEmpty }

    /// `items` in place of the readable entries, with every entry this build can't read that
    /// none of them replaces (the same key or id).
    public func replacingItems(_ items: [Element]) -> KeptList {
        let ids = Set(items.map { Self.identity(of: $0) })
        return KeptList(items: items, unreadable: unreadable.filter { $0.identity.map { !ids.contains($0) } ?? true })
    }

    /// Only the unreadable entries `keep` accepts (an exit leaves out a secret row it can't read).
    public func keepingUnreadable(where keep: (JSONValue) -> Bool) -> KeptList {
        KeptList(items: items, unreadable: unreadable.filter { keep($0.raw) })
    }

    /// Every unreadable entry changed by `transform` (an import masks a card number in one).
    public func mappingUnreadable(_ transform: (JSONValue) -> JSONValue) -> KeptList {
        KeptList(items: items, unreadable: unreadable.map { Unreadable(position: $0.position, raw: transform($0.raw)) })
    }

    private static func identity(of element: Element) -> String {
        "\(element.id)".lowercased()
    }

    // MARK: Collection

    public var startIndex: Int { items.startIndex }
    public var endIndex: Int { items.endIndex }
    public subscript(position: Int) -> Element {
        get { items[position] }
        set { items[position] = newValue }
    }

    // MARK: Coding

    public init(from decoder: Decoder) throws {
        // Almost always every entry reads: one pass. Otherwise entry by entry.
        if let all = try? [Element](from: decoder) {
            self.init(items: all, unreadable: [])
            return
        }
        let raws = try [JSONValue](from: decoder)
        var items: [Element] = []
        var unreadable: [Unreadable] = []
        for (position, raw) in raws.enumerated() {
            if let item = Self.read(raw) {
                items.append(item)
            } else {
                unreadable.append(Unreadable(position: position, raw: raw))
            }
        }
        self.init(items: items, unreadable: unreadable)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        var pending = unreadable.sorted { $0.position < $1.position }[...]
        var written = 0
        func writeUnreadable(upTo position: Int) throws {
            while let next = pending.first, next.position <= position {
                try container.encode(next.raw)
                pending = pending.dropFirst()
                written += 1
            }
        }
        for item in items {
            try writeUnreadable(upTo: written)
            try container.encode(item)
            written += 1
        }
        try writeUnreadable(upTo: .max)
    }

    /// An entry as this build reads it, or nil when it can't.
    private static func read(_ raw: JSONValue) -> Element? {
        guard let data = try? JSONEncoder().encode(raw) else { return nil }
        return try? JSONDecoder().decode(Element.self, from: data)
    }
}

extension KeptList {
    /// The list as stored in a record's JSON, with whatever couldn't be read.
    static func stored(in data: Data?) -> KeptList {
        StoredJSON.decode(KeptList.self, from: data) ?? KeptList()
    }

    /// `items` written over the list stored in `data`, keeping the entries this build can't read.
    static func writing(_ items: [Element], over data: Data?) -> Data? {
        StoredJSON.encode(stored(in: data).replacingItems(items))
    }
}

extension JSONValue {
    /// Every string inside, changed by `transform`.
    func mappingStrings(_ transform: (String) -> String) -> JSONValue {
        switch self {
        case .string(let text): .string(transform(text))
        case .array(let values): .array(values.map { $0.mappingStrings(transform) })
        case .object(let values): .object(values.mapValues { $0.mappingStrings(transform) })
        case .int, .number, .bool, .null: self
        }
    }

    /// Whether any string inside matches.
    func containsString(where match: (String) -> Bool) -> Bool {
        switch self {
        case .string(let text): match(text)
        case .array(let values): values.contains { $0.containsString(where: match) }
        case .object(let values): values.values.contains { $0.containsString(where: match) }
        case .int, .number, .bool, .null: false
        }
    }
}
