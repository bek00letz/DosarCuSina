import Foundation

/// A value stored in an asset field.
///
/// Storage and archive encoding (the `.dosar` contract):
/// - `{"type": "text", "value": "B-123-ABC"}`
/// - `{"type": "number", "value": 142500}`
/// - `{"type": "money", "amount": "350.00", "currency": "RON"}`
/// - `{"type": "date", "value": "2027-03-31"}`
/// - `{"type": "bool", "value": true}`
/// - `{"type": "choices", "value": ["Căpușe", "Purici"]}`
/// - `{"type": "contact", "name": "…", "phone": "…", "email": "…"}`
public enum FieldValue: Hashable, Sendable, Codable {
    case text(String)
    case number(Double)
    case money(Money)
    case date(CalendarDay)
    case bool(Bool)
    case choices([String])
    case contact(ContactValue)

    public enum Kind: String, Sendable {
        case text, number, money, date, bool, choices, contact
    }

    public var kind: Kind {
        switch self {
        case .text: return .text
        case .number: return .number
        case .money: return .money
        case .date: return .date
        case .bool: return .bool
        case .choices: return .choices
        case .contact: return .contact
        }
    }

    public var textValue: String? {
        if case .text(let value) = self { return value }
        return nil
    }

    public var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    public var moneyValue: Money? {
        if case .money(let value) = self { return value }
        return nil
    }

    public var dateValue: CalendarDay? {
        if case .date(let value) = self { return value }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var choicesValue: [String]? {
        if case .choices(let value) = self { return value }
        return nil
    }

    public var contactValue: ContactValue? {
        if case .contact(let value) = self { return value }
        return nil
    }

    /// True for values that carry nothing worth keeping (empty text, empty list).
    public var isEmpty: Bool {
        switch self {
        case .text(let value): return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .choices(let value): return value.isEmpty
        case .contact(let value): return value.name.isEmpty && (value.phone ?? "").isEmpty && (value.email ?? "").isEmpty
        case .number, .money, .date, .bool: return false
        }
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case type, value, amount, currency, name, phone, email, localIdentifier
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try c.decode(String.self, forKey: .value))
        case "number":
            self = .number(try c.decode(Double.self, forKey: .value))
        case "money":
            self = .money(try Money(from: decoder))
        case "date":
            self = .date(try c.decode(CalendarDay.self, forKey: .value))
        case "bool":
            self = .bool(try c.decode(Bool.self, forKey: .value))
        case "choices":
            self = .choices(try c.decode([String].self, forKey: .value))
        case "contact":
            self = .contact(ContactValue(
                name: try c.decodeIfPresent(String.self, forKey: .name) ?? "",
                phone: try c.decodeIfPresent(String.self, forKey: .phone),
                email: try c.decodeIfPresent(String.self, forKey: .email),
                localIdentifier: try c.decodeIfPresent(String.self, forKey: .localIdentifier)
            ))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown field value type \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind.rawValue, forKey: .type)
        switch self {
        case .text(let value): try c.encode(value, forKey: .value)
        case .number(let value): try c.encode(value, forKey: .value)
        case .money(let value):
            try c.encode(value.amountString, forKey: .amount)
            try c.encode(value.currency, forKey: .currency)
        case .date(let value): try c.encode(value, forKey: .value)
        case .bool(let value): try c.encode(value, forKey: .value)
        case .choices(let value): try c.encode(value, forKey: .value)
        case .contact(let value):
            try c.encode(value.name, forKey: .name)
            try c.encodeIfPresent(value.phone, forKey: .phone)
            try c.encodeIfPresent(value.email, forKey: .email)
            try c.encodeIfPresent(value.localIdentifier, forKey: .localIdentifier)
        }
    }
}

/// A set of field values keyed by `FieldDefinition.key`.
///
/// Decoding skips individual values it cannot read (for example a type added
/// by a newer app version) instead of losing the whole asset.
public struct FieldValues: Hashable, Sendable, Codable, Sequence {
    public private(set) var storage: [String: FieldValue]

    public init(_ storage: [String: FieldValue] = [:]) {
        self.storage = storage
    }

    public subscript(key: String) -> FieldValue? {
        get { storage[key] }
        set {
            if let newValue, !newValue.isEmpty {
                storage[key] = newValue
            } else {
                storage.removeValue(forKey: key)
            }
        }
    }

    public var isEmpty: Bool { storage.isEmpty }
    public var keys: [String] { storage.keys.sorted() }

    public func makeIterator() -> Dictionary<String, FieldValue>.Iterator {
        storage.makeIterator()
    }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        var result: [String: FieldValue] = [:]
        for key in c.allKeys {
            if let value = try? c.decode(FieldValue.self, forKey: key) {
                result[key.stringValue] = value
            }
        }
        storage = result
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        for (key, value) in storage {
            try c.encode(value, forKey: AnyKey(stringValue: key))
        }
    }
}
