import Foundation

/// What a field means, not just how it is stored. The type picks the input
/// control, the validator, the formatter and the stored value kind.
///
/// Raw values are part of the `.dosar` contract: never rename them.
public enum FieldType: String, Codable, CaseIterable, Sendable {
    case text
    case longText
    case number
    /// A calendar year such as 2018: a number, shown without a thousands separator.
    case year
    case money
    case date
    /// A date after which something stops being valid (documents, warranties, contracts).
    case expiryDate
    case toggle
    case choice
    case multiChoice
    case url
    case phone
    case email
    case address
    /// Romanian registration plate, such as `B-123-ABC` or `CJ-12-XYZ`.
    case plate
    /// Vehicle identification number (17 characters).
    case vin
    /// ISO 11784/11785 pet microchip (15 digits).
    case microchip
    case iban
    /// A running counter such as an odometer, engine hours or espresso shots.
    case metric
    /// A code to keep hidden, such as an identity card's PIN: sealed when saved,
    /// shown only after a fresh Face ID, never carried outside the binder (see `SecretFields`).
    case secret

    /// The kind of `FieldValue` this type stores.
    public var valueKind: FieldValue.Kind {
        switch self {
        case .number, .year, .metric: return .number
        case .money: return .money
        case .date, .expiryDate: return .date
        case .toggle: return .bool
        case .multiChoice: return .choices
        case .text, .longText, .choice, .url, .phone, .email, .address, .plate, .vin, .microchip, .iban, .secret:
            return .text
        }
    }
}

/// The job a field does in a template's presentation. Wave-2 screens build the
/// premium hero and list summaries from roles, so templates stay data.
///
/// Raw values are part of the `.dosar` contract.
public enum FieldRole: String, Codable, CaseIterable, Sendable {
    /// The value that identifies the asset at a glance: a plate, a serial number.
    case identifier
    /// A short secondary line under the asset name: make and model, breed, provider.
    case subtitle
    /// The headline number for the hero: odometer, weight.
    case heroMetric
    /// A fact worth having one tap away on the asset's top card, to copy or call:
    /// a policy number, the insurer's claims phone, a VIN, a POD code, a microchip.
    case keyFact
    /// The number of an official document (ID card, passport, licence).
    case documentNumber
    /// Who a document belongs to.
    case holder
    /// Who issued a document or policy.
    case issuer
    /// The date the asset or document stops being valid.
    case expiryDate
    /// A start date: birth date, issue date, contract start.
    case startDate
    /// When it was bought.
    case purchaseDate
    /// What it cost.
    case purchasePrice
    /// Where it was bought.
    case retailer
    /// The last day of its warranty.
    case warrantyUntil
    /// Where the asset is: an address.
    case location
}

/// One field in a category template.
public struct FieldDefinition: Hashable, Sendable, Codable, Identifiable {
    /// Stable key, unique within the template, such as `vehicle.plate`.
    public var key: String
    public var label: String
    /// A type a newer build wrote that this one doesn't know reads as `text`, and is written
    /// back as stored until the type is set here.
    public var type: FieldType { didSet { unreadable["type"] = nil } }
    public var role: FieldRole? { didSet { unreadable["role"] = nil } }
    /// Shown in the quick add flow; everything else is optional detail.
    public var isEssential: Bool
    /// Hidden behind Face ID when the category is locked (document numbers, medical data).
    public var isSensitive: Bool
    /// Options for `choice` and `multiChoice`. Values store the option keys.
    public var options: [ChoiceOption]?
    /// Unit for `number` and `metric` (kilometres, kilograms), stored by its key.
    public var unit: MeasurementUnit?
    /// Example shown in an empty field.
    public var placeholder: String?
    /// Filled in when the asset is created and the person left it empty,
    /// such as 24 months of legal guarantee. Always editable.
    public var defaultValue: FieldValue? { didSet { unreadable["defaultValue"] = nil } }
    /// Worked out from other fields while the person hasn't set it themselves.
    public var derivation: FieldDerivation? { didSet { unreadable["derivation"] = nil } }
    /// Shown and kept only while another value matches (a variant only for its
    /// document type). A value left behind when it stops applying is dropped on save.
    public var appliesWhen: BlueprintCondition? { didSet { unreadable["appliesWhen"] = nil } }
    /// One short line under the field: what it is and where to find it.
    public var footnote: String?
    /// What a newer build wrote that this one can't read (a type, a role, a default, a
    /// derivation, a condition), raw by its key: written back unchanged until that part is set
    /// here, the rule `FieldValues` follows for values.
    private var unreadable: [String: JSONValue] = [:]

    public var id: String { key }

    /// Whether the field belongs on an asset with these values.
    public func applies(to values: FieldValues) -> Bool {
        appliesWhen?.isMet(by: values) ?? true
    }

    /// The choice options offered for these values.
    public func options(for values: FieldValues) -> [ChoiceOption] {
        (options ?? []).filter { $0.isOffered(for: values) }
    }

    /// The label to show for a stored choice key (or legacy text).
    public func label(forChoice key: String) -> String {
        options?.option(for: key)?.label ?? key
    }

    /// The stored key for a choice value: keys pass through, legacy display text
    /// maps to its option's key, unknown text is kept as written.
    public func choiceKey(for text: String) -> String {
        options?.option(for: text)?.key ?? text
    }

    public init(
        key: String,
        label: String,
        type: FieldType,
        role: FieldRole? = nil,
        isEssential: Bool = false,
        isSensitive: Bool = false,
        options: [ChoiceOption]? = nil,
        unit: MeasurementUnit? = nil,
        placeholder: String? = nil,
        defaultValue: FieldValue? = nil,
        derivation: FieldDerivation? = nil,
        appliesWhen: BlueprintCondition? = nil,
        footnote: String? = nil
    ) {
        self.appliesWhen = appliesWhen
        self.footnote = footnote
        self.defaultValue = defaultValue
        self.derivation = derivation
        self.key = key
        self.label = label
        self.type = type
        self.role = role
        self.isEssential = isEssential
        self.isSensitive = isSensitive
        self.options = options
        self.unit = unit
        self.placeholder = placeholder
    }

    private enum CodingKeys: String, CodingKey {
        case key, label, type, role, isEssential, isSensitive, options, unit, placeholder, defaultValue, derivation, appliesWhen, footnote
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        label = try c.decode(String.self, forKey: .label)
        // Unknown types from a newer app version read as text instead of failing the import,
        // and are kept as written.
        let storedType = try c.decode(String.self, forKey: .type)
        type = FieldType(rawValue: storedType) ?? .text
        let storedRole = try c.decodeIfPresent(String.self, forKey: .role)
        role = storedRole.flatMap(FieldRole.init(rawValue:))
        isEssential = try c.decodeIfPresent(Bool.self, forKey: .isEssential) ?? false
        isSensitive = try c.decodeIfPresent(Bool.self, forKey: .isSensitive) ?? false
        options = try c.decodeIfPresent([ChoiceOption].self, forKey: .options)
        // Any label written so far ("m³", "luni") reads as its unit; it is written back as the key.
        unit = MeasurementUnit(try c.decodeIfPresent(String.self, forKey: .unit))
        placeholder = try c.decodeIfPresent(String.self, forKey: .placeholder)
        defaultValue = try? c.decodeIfPresent(FieldValue.self, forKey: .defaultValue)
        derivation = try? c.decodeIfPresent(FieldDerivation.self, forKey: .derivation)
        appliesWhen = try? c.decodeIfPresent(BlueprintCondition.self, forKey: .appliesWhen)
        footnote = try c.decodeIfPresent(String.self, forKey: .footnote)
        var kept: [String: JSONValue] = [:]
        if FieldType(rawValue: storedType) == nil { kept["type"] = .string(storedType) }
        if let storedRole, role == nil { kept["role"] = .string(storedRole) }
        for (key, read) in [(CodingKeys.defaultValue, defaultValue != nil), (.derivation, derivation != nil), (.appliesWhen, appliesWhen != nil)]
        where !read && c.contains(key) {
            if let raw = try? c.decode(JSONValue.self, forKey: key), raw != .null { kept[key.rawValue] = raw }
        }
        unreadable = kept
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
        try c.encode(label, forKey: .label)
        try c.encode(isEssential, forKey: .isEssential)
        try c.encode(isSensitive, forKey: .isSensitive)
        try c.encodeIfPresent(options, forKey: .options)
        try c.encodeIfPresent(unit, forKey: .unit)
        try c.encodeIfPresent(placeholder, forKey: .placeholder)
        try c.encodeIfPresent(footnote, forKey: .footnote)
        func write<Value: Encodable>(_ value: Value?, _ key: CodingKeys) throws {
            if let raw = unreadable[key.rawValue] {
                try c.encode(raw, forKey: key)
            } else {
                try c.encodeIfPresent(value, forKey: key)
            }
        }
        try write(type, .type)
        try write(role, .role)
        try write(defaultValue, .defaultValue)
        try write(derivation, .derivation)
        try write(appliesWhen, .appliesWhen)
    }
}

/// How a field is worked out from others.
///
/// Encoding: `{"type": "addMonths", "date": "purchase.date", "months": "purchase.warrantyMonths"}`.
public enum FieldDerivation: Hashable, Sendable, Codable {
    /// A date field plus a number of months from another field (purchase date + warranty months).
    case addMonths(dateField: String, monthsField: String)
    /// A document's last valid day from the day it was issued, when its type and variant
    /// have a documented validity (`DocumentType.validityMonthsAfterIssue`: a cazier
    /// judiciar, six months).
    case validityAfterIssue(issueField: String)

    private enum CodingKeys: String, CodingKey { case type, date, months }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "addMonths":
            self = .addMonths(dateField: try c.decode(String.self, forKey: .date), monthsField: try c.decode(String.self, forKey: .months))
        case "validityAfterIssue":
            self = .validityAfterIssue(issueField: try c.decode(String.self, forKey: .date))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown derivation")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .addMonths(let date, let months):
            try c.encode("addMonths", forKey: .type)
            try c.encode(date, forKey: .date)
            try c.encode(months, forKey: .months)
        case .validityAfterIssue(let issue):
            try c.encode("validityAfterIssue", forKey: .type)
            try c.encode(issue, forKey: .date)
        }
    }

    /// The fields this derivation reads.
    public var inputs: [String] {
        switch self {
        case .addMonths(let date, let months): return [date, months]
        case .validityAfterIssue(let issue): return [issue, DocumentType.typeFieldKey, DocumentType.variantFieldKey]
        }
    }

    public func value(from values: FieldValues, calendar: Calendar = .current) -> FieldValue? {
        switch self {
        case .addMonths(let dateField, let monthsField):
            guard let day = values[dateField]?.dateValue, let months = values[monthsField]?.numberValue, months > 0 else { return nil }
            return .date(RecurrenceEngine.add(.months(Int(months)), to: day, calendar: calendar))
        case .validityAfterIssue(let issueField):
            guard let issued = values[issueField]?.dateValue,
                  let until = DocumentType.validUntil(issued: issued, type: values[DocumentType.typeFieldKey]?.textValue,
                                                      variant: values[DocumentType.variantFieldKey]?.textValue, calendar: calendar) else { return nil }
            return .date(until)
        }
    }
}

/// A titled group of fields, shown as one section on the asset screen.
public struct FieldSection: Hashable, Sendable, Codable, Identifiable {
    public var key: String
    public var title: String
    public var fields: [FieldDefinition]

    public var id: String { key }

    public init(key: String, title: String, fields: [FieldDefinition]) {
        self.key = key
        self.title = title
        self.fields = fields
    }
}
