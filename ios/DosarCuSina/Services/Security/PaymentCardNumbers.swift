import Foundation

/// What a section's field types say about its values, beside the card rule itself
/// (`CardNumberRule.swift` in `ios/Shared`, which reads text alone, so the share extension
/// uses it too): which values stay whole because their field
/// says what they are (`keepsWhole`), how a section's values and rows are masked
/// (`sanitizing`), and the digits a section keeps whole in all its words (`KeptWhole`).
extension PaymentCardNumbers {
    /// The field types whose own check tells their value apart from a card number: an IBAN
    /// (country letters and its mod-97 check digits) and a pet's microchip (ISO 11784, 15 digits).
    /// A phone, a VIN or a plain number is not among them: their checks also let a card number through.
    static let typesKeptWhole: Set<FieldType> = [.iban, .microchip]

    /// Whether a field's value is kept whole, never masked: its type names what it is
    /// (`typesKeptWhole`) and it passes that type's own check (`FieldFormatter.validate`).
    public static func keepsWhole(_ text: String, as type: FieldType?) -> Bool {
        guard let type, typesKeptWhole.contains(type) else { return false }
        return FieldFormatter.validate(text, as: type) == .valid
    }

    /// The same values with every text masked by the "anywhere" rule, and the fields that
    /// keep only the last digits (`DocumentFields.cardLastFour`) cut to them. A value whose
    /// field (from `fields`, read only when something would be masked) has a type that tells
    /// it apart (`keepsWhole`) stays as typed, and so do the same digits in another of the
    /// values (`KeptWhole`): a note that repeats the microchip.
    public static func sanitizing(_ values: FieldValues, fields: () -> [FieldDefinition]) -> FieldValues {
        // A value this build can't read is masked the same way, wherever text sits in it.
        var result = values.mappingUnreadable { redacting($0) }
        var fieldsRead = false
        var types: [String: FieldType] = [:]
        var kept = KeptWhole.nothing
        for (key, value) in values.storage {
            // A sealed code is the secret's own business, never rewritten.
            guard case .text(let text) = value, !SecretSealer.isSealed(text) else { continue }
            if key == DocumentFields.cardLastFour {
                result[key] = lastFour(of: text).map(FieldValue.text)
                continue
            }
            guard redact(text) != text else { continue }
            if !fieldsRead {
                let all = fields()
                fieldsRead = true
                types = Dictionary(all.map { ($0.key, $0.type) }, uniquingKeysWith: { first, _ in first })
                kept = KeptWhole(values, fields: all)
            }
            if !keepsWhole(text, as: types[key]) { result[key] = .text(redact(text, keeping: kept)) }
        }
        return result
    }

    /// The same for values as stored, and in what a newer build wrote inside a value this
    /// build reads (`KeptObject.mappingKept`).
    public static func sanitizing(_ values: KeptObject<FieldValues>, fields: () -> [FieldDefinition]) -> KeptObject<FieldValues> {
        values.replacingValue(sanitizing(values.value, fields: fields)).mappingKept { redacting($0) }
    }

    /// Rows under Date importante with every card number masked, in their labels and values, in
    /// the rows this build can't read and in what a newer build wrote inside the rows it reads.
    /// What the section keeps whole (`kept`) stays. A secret row's sealed code is the secret's
    /// own business.
    public static func sanitizing(_ facts: KeptList<CustomFact>, keeping kept: KeptWhole = .nothing) -> KeptList<CustomFact> {
        let masked = facts.items.map { fact in
            var fact = fact
            fact.label = redact(fact.label, keeping: kept)
            if !SecretSealer.isSealed(fact.value) { fact.value = redact(fact.value, keeping: kept) }
            return fact
        }
        return facts.replacingItems(masked).mappingKept { redacting($0) }
    }

    /// Raw JSON a newer build wrote, with any card number in its text masked; sealed codes stay.
    public static func redacting(_ raw: JSONValue) -> JSONValue {
        raw.mappingStrings { SecretSealer.isSealed($0) ? $0 : redact($0) }
    }
}

extension PaymentCardNumbers.KeptWhole {
    /// What a section's values keep whole: each value its own field's type keeps whole
    /// (`keepsWhole`) and that is digits alone (a microchip). An IBAN is left whole by the text
    /// rule wherever it is printed (`IBAN.ranges`), so it needs nothing here.
    public init(_ values: FieldValues, fields: [FieldDefinition]) {
        self.init(typed: fields.compactMap { field in values[field.key]?.textValue.map { (text: $0, type: field.type) } })
    }

    /// The same for values with their types, as capture reads them (`CaptureFieldKey.typeKeptWhole`).
    public init(typed values: [(text: String, type: FieldType)]) {
        let digits = values.compactMap { value -> String? in
            guard PaymentCardNumbers.keepsWhole(value.text, as: value.type),
                  value.text.allSatisfy({ ($0.isASCII && $0.isNumber) || $0 == " " || $0 == "-" }) else { return nil }
            let digits = value.text.filter { $0.isASCII && $0.isNumber }
            return digits.isEmpty ? nil : digits
        }
        self.init(checkedDigits: Set(digits))
    }

    /// What a section keeps whole: its values, through its category's fields. Nothing without
    /// a section or its category.
    public init(section: Asset?, template: CategoryTemplate?) {
        guard let section, let template else {
            self = .nothing
            return
        }
        self.init(section.values, fields: template.definition.allFields)
    }
}

extension PaymentCardNetwork {
    public static var options: [ChoiceOption] {
        [
            ChoiceOption(key: visa, label: "Visa", aliases: ["Visa Debit", "Visa Electron", "Visa Classic", "Visa Gold", "Visa Platinum"]),
            ChoiceOption(key: mastercard, label: "Mastercard", aliases: ["MasterCard", "Debit Mastercard", "Mastercard Gold", "World Mastercard"]),
            ChoiceOption(key: maestro, label: "Maestro"),
            ChoiceOption(key: amex, label: "American Express", aliases: ["Amex"]),
            ChoiceOption(key: other, label: String(localized: "Altă rețea"), aliases: ["Altul"]),
        ]
    }

    /// The network's name: "Visa".
    public static func label(for key: String?) -> String? {
        key.flatMap { options.option(for: $0)?.label }
    }

    /// The words that name a network on the card, folded, most specific first.
    static let words: [(network: String, names: [String])] = [
        (maestro, ["maestro"]),
        (mastercard, ["mastercard", "master card"]),
        (amex, ["american express", "amex"]),
        (visa, ["visa"]),
    ]

    /// The network the card's printed words name, matched as whole words.
    static func read(in folded: String) -> String? {
        words.first { entry in entry.names.contains { CaptureText.containsWord($0, inFolded: folded) } }?.network
    }
}
