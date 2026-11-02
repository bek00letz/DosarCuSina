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

    /// The kind of `FieldValue` this type stores.
    public var valueKind: FieldValue.Kind {
        switch self {
        case .number, .year, .metric: return .number
        case .money: return .money
        case .date, .expiryDate: return .date
        case .toggle: return .bool
        case .multiChoice: return .choices
        case .text, .longText, .choice, .url, .phone, .email, .address, .plate, .vin, .microchip, .iban:
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
    public var type: FieldType
    public var role: FieldRole?
    /// Shown in the quick add flow; everything else is optional detail.
    public var isEssential: Bool
    /// Hidden behind Face ID when the category is locked (document numbers, medical data).
    public var isSensitive: Bool
    /// Options for `choice` and `multiChoice`. Values store the option keys.
    public var options: [ChoiceOption]?
    /// Unit for `number` and `metric`, such as `km` or `kg`.
    public var unit: String?
    /// Example shown in an empty field.
    public var placeholder: String?
    /// Filled in when the asset is created and the person left it empty,
    /// such as 24 months of legal guarantee. Always editable.
    public var defaultValue: FieldValue?
    /// Worked out from other fields while the person hasn't set it themselves.
    public var derivation: FieldDerivation?
    /// Shown and kept only while another value matches (a variant only for its
    /// document type). A value left behind when it stops applying is dropped on save.
    public var appliesWhen: BlueprintCondition?
    /// One short line under the field: what it is and where to find it.
    public var footnote: String?

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
        unit: String? = nil,
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
        // Unknown types from a newer app version fall back to text instead of failing the import.
        type = FieldType(rawValue: try c.decode(String.self, forKey: .type)) ?? .text
        role = (try c.decodeIfPresent(String.self, forKey: .role)).flatMap(FieldRole.init(rawValue:))
        isEssential = try c.decodeIfPresent(Bool.self, forKey: .isEssential) ?? false
        isSensitive = try c.decodeIfPresent(Bool.self, forKey: .isSensitive) ?? false
        options = try c.decodeIfPresent([ChoiceOption].self, forKey: .options)
        unit = try c.decodeIfPresent(String.self, forKey: .unit)
        placeholder = try c.decodeIfPresent(String.self, forKey: .placeholder)
        defaultValue = try? c.decodeIfPresent(FieldValue.self, forKey: .defaultValue)
        derivation = try? c.decodeIfPresent(FieldDerivation.self, forKey: .derivation)
        appliesWhen = try? c.decodeIfPresent(BlueprintCondition.self, forKey: .appliesWhen)
        footnote = try c.decodeIfPresent(String.self, forKey: .footnote)
    }
}

/// How a field is worked out from others.
///
/// Encoding: `{"type": "addMonths", "date": "purchase.date", "months": "purchase.warrantyMonths"}`.
public enum FieldDerivation: Hashable, Sendable, Codable {
    /// A date field plus a number of months from another field (purchase date + warranty months).
    case addMonths(dateField: String, monthsField: String)

    private enum CodingKeys: String, CodingKey { case type, date, months }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "addMonths":
            self = .addMonths(dateField: try c.decode(String.self, forKey: .date), monthsField: try c.decode(String.self, forKey: .months))
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
        }
    }

    /// The fields this derivation reads.
    public var inputs: [String] {
        switch self {
        case .addMonths(let date, let months): return [date, months]
        }
    }

    public func value(from values: FieldValues, calendar: Calendar = .current) -> FieldValue? {
        switch self {
        case .addMonths(let dateField, let monthsField):
            guard let day = values[dateField]?.dateValue, let months = values[monthsField]?.numberValue, months > 0 else { return nil }
            return .date(RecurrenceEngine.add(.months(Int(months)), to: day, calendar: calendar))
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
