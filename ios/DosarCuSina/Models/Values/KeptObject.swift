import Foundation

/// One object stored as JSON that a newer build may have written: a category's behaviour, a
/// deadline's recurrence, a document's framing, a section's values. The value this build reads,
/// and the JSON it was read from, so writing it again keeps every key this build doesn't know,
/// at any depth, and every value it read as something else, as stored (`JSONValue.laying`).
///
/// It is the rule `KeptList` follows for a list's entries and `FieldValues` for values: keep
/// what can't be read, raw, and never write back less than was stored. Code reads and edits
/// `value`; a record's plain accessor (`Asset.values`, `CategoryTemplate.behavior`) does it for
/// it. A value made here, with nothing read, writes as it always did.
public struct KeptObject<Value: Codable & Hashable & Sendable>: Hashable, Sendable, Codable {
    /// The value as this build reads it, with any edit.
    public var value: Value
    /// The JSON it was read from and the value read from it, or nil for a value made here.
    private var origin: Origin?

    private struct Origin: Hashable, Sendable {
        let stored: JSONValue
        let asRead: Value
    }

    /// A value made here: nothing kept beside it.
    public init(_ value: Value) {
        self.value = value
        self.origin = nil
    }

    /// `stored`, which this build read as `asRead` (its fallback when it can't read it at all).
    init(stored: JSONValue, asRead: Value) {
        self.value = asRead
        self.origin = Origin(stored: stored, asRead: asRead)
    }

    private init(value: Value, origin: Origin?) {
        self.value = value
        self.origin = origin
    }

    /// The same, with `value` in place of this one's: what it kept stays.
    public func replacingValue(_ value: Value) -> KeptObject {
        KeptObject(value: value, origin: origin)
    }

    /// The JSON it writes: the value laid over what it was read from.
    var json: JSONValue? {
        guard let edited = JSONValue(encoding: value) else { return nil }
        guard let origin else { return edited }
        if value == origin.asRead { return origin.stored }
        guard let read = JSONValue(encoding: origin.asRead) else { return edited }
        return .laying(edited, over: origin.stored, readAs: read)
    }

    /// Whether it writes anything `value` doesn't say: something a newer build wrote.
    public var keepsMore: Bool {
        origin != nil && json != JSONValue(encoding: value)
    }

    /// Every part kept that this build doesn't read changed by `transform`, or left out when it
    /// gives nil (`JSONValue.mappingKept`): the rules every exit applies reach them too.
    public func mappingKept(_ transform: (JSONValue) -> JSONValue?) -> KeptObject {
        guard let origin, let read = JSONValue(encoding: origin.asRead) else { return self }
        return KeptObject(value: value, origin: Origin(stored: origin.stored.mappingKept(readAs: read, transform), asRead: origin.asRead))
    }

    /// Nil when it is `isDefault` and keeps nothing more: a record stores nothing then.
    public func omitted(when isDefault: (Value) -> Bool) -> KeptObject? {
        isDefault(value) && !keepsMore ? nil : self
    }

    // MARK: Coding

    public init(from decoder: Decoder) throws {
        let stored = try JSONValue(from: decoder)
        let read = try Value(from: decoder)
        self.init(stored: stored, asRead: read)
    }

    public func encode(to encoder: Encoder) throws {
        guard origin != nil else { return try value.encode(to: encoder) }
        guard let json else {
            throw EncodingError.invalidValue(value, .init(codingPath: encoder.codingPath, debugDescription: "Not writable as JSON"))
        }
        try json.encode(to: encoder)
    }
}

extension KeptObject {
    /// The object a record keeps in `data`, with what this build doesn't read; nil when there is
    /// none (or it isn't JSON). Read with `fallback` when this build can't read it at all.
    static func stored(in data: Data?, fallback: Value) -> KeptObject? {
        guard let data, let stored = StoredJSON.decode(JSONValue.self, from: data) else { return nil }
        return KeptObject(stored: stored, asRead: StoredJSON.decode(Value.self, from: data) ?? fallback)
    }

    /// Only the value a record keeps in `data`, for reading: the same value `stored(in:)` reads.
    static func value(in data: Data?) -> Value? {
        StoredJSON.decode(Value.self, from: data)
    }

    /// What a record stores for `kept`: nothing when it is `isDefault` and keeps nothing more.
    static func data(_ kept: KeptObject?, omittedWhen isDefault: (Value) -> Bool = { _ in false }) -> Data? {
        kept?.omitted(when: isDefault).flatMap { StoredJSON.encode($0) }
    }
}
