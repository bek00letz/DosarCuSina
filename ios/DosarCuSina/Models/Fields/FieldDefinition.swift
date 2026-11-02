import Foundation

/// What a field means, not just how it is stored. The type picks the input
/// control, the validator, the formatter and the stored value kind.
///
/// Raw values are part of the `.dosar` contract: never rename them.
public enum FieldType: String, Codable, CaseIterable, Sendable {
    case text
    case longText
    case number
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
        case .number, .metric: return .number
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
    /// Options for `choice` and `multiChoice`.
    public var options: [String]?
    /// Unit for `number` and `metric`, such as `km` or `kg`.
    public var unit: String?
    /// Example shown in an empty field.
    public var placeholder: String?

    public var id: String { key }

    public init(
        key: String,
        label: String,
        type: FieldType,
        role: FieldRole? = nil,
        isEssential: Bool = false,
        isSensitive: Bool = false,
        options: [String]? = nil,
        unit: String? = nil,
        placeholder: String? = nil
    ) {
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
        case key, label, type, role, isEssential, isSensitive, options, unit, placeholder
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
        options = try c.decodeIfPresent([String].self, forKey: .options)
        unit = try c.decodeIfPresent(String.self, forKey: .unit)
        placeholder = try c.decodeIfPresent(String.self, forKey: .placeholder)
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
