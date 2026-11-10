import Foundation

/// A list stored as JSON that a newer build may have written: the entries this build can
/// read, and the ones it can't, kept raw in their places and written back unchanged. A
/// template's sections, deadlines and parts, and a section's rows under Date importante.
///
/// It is the rule `FieldValues` follows for values: keep what can't be read, raw, and never
/// write back less than was stored. An entry this build can't read goes only when one it
/// can read takes its place (the same key or id), so editing the readable ones never loses
/// the others. An entry it reads keeps the JSON it was read from, by its key or id, and is
/// written over it (`JSONValue.laying`, the rule `KeptObject` follows for one object), so a
/// key inside it that this build doesn't know stays too. Reading code sees `items` (or the
/// list itself, a collection of them).
public struct KeptList<Element: Codable & Hashable & Sendable & Identifiable>: Hashable, Sendable, Codable, RandomAccessCollection, MutableCollection, ExpressibleByArrayLiteral {
    /// The entries this build reads, in order.
    public var items: [Element]
    /// The entries it can't, raw, each with its place in the list as it was read.
    public private(set) var unreadable: [Unreadable]
    /// The JSON each entry it reads was read from, and the entry read from it, by its key or id.
    private var origins: [String: Origin] = [:]

    public struct Unreadable: Hashable, Sendable {
        /// Its place among all the entries, readable or not, when it was read.
        public let position: Int
        public let raw: JSONValue

        /// The key or id it is known by, when it has one this build can read.
        var identity: String? { raw.keptIdentity }
    }

    private struct Origin: Hashable, Sendable {
        let stored: JSONValue
        let asRead: Element
    }

    public init(_ items: [Element] = []) {
        self.items = items
        self.unreadable = []
    }

    public init(arrayLiteral elements: Element...) {
        self.init(elements)
    }

    private init(items: [Element], unreadable: [Unreadable], origins: [String: Origin]) {
        self.items = items
        self.unreadable = unreadable
        self.origins = origins
    }

    /// Whether every entry could be read.
    public var isFullyRead: Bool { unreadable.isEmpty }

    /// `items` in place of the readable entries, with every entry this build can't read that
    /// none of them replaces (the same key or id). An entry keeps what it was read from while one
    /// with its key or id is among them.
    public func replacingItems(_ items: [Element]) -> KeptList {
        let ids = Set(items.map { Self.identity(of: $0) })
        return KeptList(items: items, unreadable: unreadable.filter { $0.identity.map { !ids.contains($0) } ?? true },
                        origins: origins.filter { ids.contains($0.key) })
    }

    /// Every part kept that this build doesn't read changed by `transform`, or left out when it
    /// gives nil: an entry it can't read, whole, and inside an entry it reads, what it doesn't
    /// read there (`JSONValue.mappingKept`). The rules every exit applies (a secret row left out
    /// of a backup, a card number masked on the way in) reach them too.
    public func mappingKept(_ transform: (JSONValue) -> JSONValue?) -> KeptList {
        let kept = unreadable.compactMap { entry in transform(entry.raw).map { Unreadable(position: entry.position, raw: $0) } }
        let mapped = origins.mapValues { origin -> Origin in
            guard let read = JSONValue(encoding: origin.asRead) else { return origin }
            return Origin(stored: origin.stored.mappingKept(readAs: read, transform), asRead: origin.asRead)
        }
        return KeptList(items: items, unreadable: kept, origins: mapped)
    }

    /// Only the entries `isIncluded` keeps, readable or not: a readable one with the JSON it was
    /// read from, one this build can't read raw.
    public func filtered(_ isIncluded: (Element) -> Bool, unreadable keepsRaw: (JSONValue) -> Bool) -> KeptList {
        let items = items.filter(isIncluded)
        let ids = Set(items.map { Self.identity(of: $0) })
        return KeptList(items: items, unreadable: unreadable.filter { keepsRaw($0.raw) }, origins: origins.filter { ids.contains($0.key) })
    }

    /// The keys or ids of every entry, readable or not.
    public var identities: Set<String> {
        Set(items.map { Self.identity(of: $0) }).union(unreadable.compactMap(\.identity))
    }

    /// This list without the entries `other` has (the same key or id), then `other`'s entries,
    /// readable or not, each with what it kept: `other` takes the place of what it replaces.
    public func replacingEntries(with other: KeptList) -> KeptList {
        let ids = other.identities
        let kept = filtered({ !ids.contains(Self.identity(of: $0)) }, unreadable: { raw in raw.keptIdentity.map { !ids.contains($0) } ?? true })
        let start = kept.items.count + kept.unreadable.count
        return KeptList(
            items: kept.items + other.items,
            unreadable: kept.unreadable + other.unreadable.map { Unreadable(position: start + $0.position, raw: $0.raw) },
            origins: kept.origins.merging(other.origins) { _, theirs in theirs }
        )
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
        let raws = try [JSONValue](from: decoder)
        // Almost always every entry reads: one pass. Otherwise entry by entry.
        let all = (try? [Element](from: decoder)).flatMap { $0.count == raws.count ? $0 : nil }
        var items: [Element] = []
        var unreadable: [Unreadable] = []
        var origins: [String: Origin] = [:]
        for (position, raw) in raws.enumerated() {
            if let item = all?[position] ?? raw.decoded(as: Element.self) {
                items.append(item)
                let id = Self.identity(of: item)
                if origins[id] == nil { origins[id] = Origin(stored: raw, asRead: item) }
            } else {
                unreadable.append(Unreadable(position: position, raw: raw))
            }
        }
        self.init(items: items, unreadable: unreadable, origins: origins)
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
            if let json = laidOver(item) {
                try container.encode(json)
            } else {
                try container.encode(item)
            }
            written += 1
        }
        try writeUnreadable(upTo: .max)
    }

    /// An entry as it is written over the JSON it was read from, or nil for one made here.
    private func laidOver(_ item: Element) -> JSONValue? {
        guard let origin = origins[Self.identity(of: item)] else { return nil }
        if item == origin.asRead { return origin.stored }
        guard let edited = JSONValue(encoding: item), let read = JSONValue(encoding: origin.asRead) else { return nil }
        return .laying(edited, over: origin.stored, readAs: read)
    }
}

extension KeptList {
    /// The list as stored in a record's JSON, with whatever couldn't be read.
    static func stored(in data: Data?) -> KeptList {
        StoredJSON.decode(KeptList.self, from: data) ?? KeptList()
    }

    /// Only the entries this build reads, for reading: the same entries `stored(in:)` reads.
    static func items(in data: Data?) -> [Element] {
        guard let data else { return [] }
        return StoredJSON.decode([Element].self, from: data) ?? stored(in: data).items
    }

    /// `items` written over the list stored in `data`, keeping the entries this build can't read
    /// and, inside the ones it reads, what it doesn't read there.
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
