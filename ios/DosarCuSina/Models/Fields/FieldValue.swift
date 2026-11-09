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
///
/// People are not field values: they are `Provider` records linked to the asset.
public enum FieldValue: Hashable, Sendable, Codable {
    case text(String)
    case number(Double)
    case money(Money)
    case date(CalendarDay)
    case bool(Bool)
    case choices([String])

    public enum Kind: String, Sendable {
        case text, number, money, date, bool, choices
    }

    public var kind: Kind {
        switch self {
        case .text: return .text
        case .number: return .number
        case .money: return .money
        case .date: return .date
        case .bool: return .bool
        case .choices: return .choices
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

    /// True for values that carry nothing worth keeping (empty text, empty list).
    public var isEmpty: Bool {
        switch self {
        case .text(let value): return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .choices(let value): return value.isEmpty
        case .number, .money, .date, .bool: return false
        }
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case type, value, amount, currency
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
        }
    }
}

/// A set of field values keyed by `FieldDefinition.key`.
///
/// Decoding skips individual values it cannot read (for example a type added
/// by a newer app version) instead of losing the whole asset.
public struct FieldValues: Hashable, Sendable, Codable, Sequence {
    public private(set) var storage: [String: FieldValue]
    /// Values this build can't read (a value kind from a newer build or archive), kept as
    /// they were stored and written back unchanged. Gone only when the field gets a new value.
    private var unreadable: [String: JSONValue] = [:]

    public init(_ storage: [String: FieldValue] = [:]) {
        self.storage = storage
    }

    public subscript(key: String) -> FieldValue? {
        get { storage[key] }
        set {
            unreadable.removeValue(forKey: key)
            if let newValue, !newValue.isEmpty {
                storage[key] = newValue
            } else {
                storage.removeValue(forKey: key)
            }
        }
    }

    public var isEmpty: Bool { storage.isEmpty }

    /// The same values with every value this build can't read changed by `transform`, or left
    /// out when it returns nil: the rules every exit applies (secrets, card numbers) reach them too.
    public func mappingUnreadable(_ transform: (JSONValue) -> JSONValue?) -> FieldValues {
        var result = self
        result.unreadable = unreadable.compactMapValues(transform)
        return result
    }

    /// The values with defaults filled in for empty fields (new assets only) and
    /// derived fields worked out again when one of their inputs changed, or when
    /// they are still empty. A derived value the person typed in themselves stays
    /// until an input changes, and one given in the same change as its inputs (a
    /// contract's printed end date, beside its start and length) is kept as given.
    public func applyingRules(of template: TemplateDefinition, previous: FieldValues?, calendar: Calendar = .current) -> FieldValues {
        var result = self
        if previous == nil {
            for field in template.allFields where result[field.key] == nil {
                if let value = field.defaultValue { result[field.key] = value }
            }
        }
        // Values that no longer belong (a cazier's variant after the type became a
        // passport) go. Twice, so a value that depended on a dropped one goes too.
        for _ in 0..<2 {
            for field in template.allFields {
                if !field.applies(to: result) {
                    result[field.key] = nil
                } else if field.type == .choice, let key = result[field.key]?.textValue,
                          let option = field.options?.option(for: key), !option.isOffered(for: result) {
                    result[field.key] = nil
                }
            }
        }
        for field in template.allFields {
            guard let derivation = field.derivation else { continue }
            let inputsChanged = previous.map { old in derivation.inputs.contains { old[$0] != result[$0] } } ?? true
            let givenNow = previous.map { $0[field.key] != result[field.key] } ?? (result[field.key] != nil)
            if result[field.key] == nil || (inputsChanged && !givenNow), let value = derivation.value(from: result, calendar: calendar) {
                result[field.key] = value
            }
        }
        return result
    }

    /// The same values with choice fields stored as option keys. Display text
    /// written before keys existed (older backups, earlier builds) maps to its
    /// key; text no option recognizes is kept as written.
    public func normalizingChoices(for template: TemplateDefinition) -> FieldValues {
        var result = self
        for field in template.allFields where field.options != nil {
            switch (field.type, storage[field.key]) {
            case (.choice, .text(let text)?):
                result[field.key] = .text(field.choiceKey(for: text))
            case (.multiChoice, .choices(let items)?):
                result[field.key] = .choices(items.map(field.choiceKey(for:)))
            case (.multiChoice, .text(let text)?):
                result[field.key] = .choices([field.choiceKey(for: text)])
            default:
                break
            }
        }
        return result
    }
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
        var kept: [String: JSONValue] = [:]
        for key in c.allKeys {
            if let value = try? c.decode(FieldValue.self, forKey: key) {
                result[key.stringValue] = value
            } else if let raw = try? c.decode(JSONValue.self, forKey: key) {
                kept[key.stringValue] = raw
            }
        }
        storage = result
        unreadable = kept
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        for (key, value) in storage {
            try c.encode(value, forKey: AnyKey(stringValue: key))
        }
        for (key, raw) in unreadable where storage[key] == nil {
            try c.encode(raw, forKey: AnyKey(stringValue: key))
        }
    }
}
