import Foundation

/// The unit a reading, a number field or a counted recurrence is in, known by a stable key.
///
/// The key is the unit's identity: readings are grouped by it, a metric deadline finds its
/// counter by it, and it is what the database and `.dosar` archives store (`km`, `h`, `kwh`,
/// `m3`, `gcal`, …). What a person sees is `label` ("kWh", "m³", "cafele"), which may be
/// translated and never takes part in a comparison.
///
/// - Reading accepts every form written so far: the key, the label, the spellings earlier
///   versions stored ("m³", "mc", "kWh", "luni", "cafele") and the label in the app's
///   language, ignoring case, diacritics and superscripts. So stored data and older archives
///   read without a migration.
/// - A unit outside the catalog (a category of the person's own, "ore motor") is kept as
///   written: its key is that text, trimmed, and it shows as written.
/// - Writing always writes the key.
public struct MeasurementUnit: Hashable, Sendable, Codable, CustomStringConvertible {
    /// The stable key: a catalog key, or the person's own unit as written.
    public let key: String

    private init(key: String) {
        self.key = key
    }

    // MARK: The catalog

    public static let kilometres = MeasurementUnit(key: "km")
    public static let engineHours = MeasurementUnit(key: "h")
    public static let kilowattHours = MeasurementUnit(key: "kwh")
    public static let cubicMetres = MeasurementUnit(key: "m3")
    public static let gigacalories = MeasurementUnit(key: "gcal")
    public static let kilograms = MeasurementUnit(key: "kg")
    public static let milligramsPerDecilitre = MeasurementUnit(key: "mgdl")
    public static let millimetresOfMercury = MeasurementUnit(key: "mmhg")
    public static let dioptres = MeasurementUnit(key: "dpt")
    public static let cubicCentimetres = MeasurementUnit(key: "cm3")
    public static let horsepower = MeasurementUnit(key: "hp")
    public static let squareMetres = MeasurementUnit(key: "m2")
    public static let months = MeasurementUnit(key: "months")
    /// Coffees made by an espresso machine.
    public static let shots = MeasurementUnit(key: "shots")

    /// Every unit the app knows, with its label and every spelling it may have been stored with.
    public static let catalog: [MeasurementUnit] = [
        .kilometres, .engineHours, .kilowattHours, .cubicMetres, .gigacalories, .kilograms,
        .milligramsPerDecilitre, .millimetresOfMercury, .dioptres, .cubicCentimetres, .horsepower,
        .squareMetres, .months, .shots,
    ]

    /// Units a meter index printed on a bill may carry after its number.
    public static let meterUnits: [MeasurementUnit] = [.cubicMetres, .kilowattHours, .gigacalories, .kilograms]

    /// Whether the key is one of the catalog's, rather than the person's own unit.
    public var isCatalog: Bool { Self.catalog.contains(self) }

    /// What a person sees after a number: "km", "kWh", "m³", "cafele". A unit of the
    /// person's own shows as written.
    public var label: String {
        switch key {
        case "km": "km"
        case "h": "h"
        case "kwh": "kWh"
        case "m3": "m³"
        case "gcal": "Gcal"
        case "kg": "kg"
        case "mgdl": "mg/dL"
        case "mmhg": "mmHg"
        case "dpt": "dpt"
        case "cm3": "cm³"
        case "hp": "CP"
        case "m2": "m²"
        case "months": String(localized: "luni", comment: "Unit after a number of months, e.g. '24 luni' of warranty.")
        case "shots": String(localized: "cafele", comment: "Unit after the number of coffees an espresso machine has made, e.g. '1.250 cafele'.")
        default: key
        }
    }

    public var description: String { label }

    /// A number with its unit, as the app writes it: "45.724 km", "12,5 m³", "1.250 de cafele";
    /// the number alone when there is no unit. The one way a number and its unit are written
    /// (`after(_:value:)`).
    public static func written(_ value: Double, in unit: MeasurementUnit?, fractionDigits: ClosedRange<Int> = 0...1) -> String {
        let number = RomanianNumber.format(Decimal(value), fractionDigits: fractionDigits)
        guard let unit else { return number }
        return unit.after(number, value: value)
    }

    /// `number`, already written („1.250”), followed by this unit, kept on one line with a
    /// no-break space: a symbol as it is („45.724 km”, „12,5 m³”); a counted word („cafele”,
    /// „luni”) counted as Romanian counts it, from the String Catalog's plural forms, like the leu
    /// in `Money`: „1 cafea”, „2 cafele”, „19 cafele”, „20 de cafele”, „101 cafele”,
    /// „1.250 de cafele”, with „de” before the unit from 20 on. A value with decimals takes the
    /// word as after 2 („1,5 luni”). `value` only chooses the form.
    public func after(_ number: String, value: Double) -> String {
        let count = Self.wholeCount(value)
        switch key {
        case "shots":
            guard let count else { return "\(number)\u{00A0}\(label)" }
            return String(localized: "\(number)\u{00A0}\(count) cafele",
                          locale: .dosarDefault, comment: "A number of coffees an espresso machine made: the first argument is the number as written („1.250”), the second only chooses the plural („1 cafea”, „2 cafele”, „20 de cafele”). Keep the no-break spaces.")
        case "months":
            guard let count else { return "\(number)\u{00A0}\(label)" }
            return String(localized: "\(number)\u{00A0}\(count) luni",
                          locale: .dosarDefault, comment: "A number of months: the first argument is the number as written („24”), the second only chooses the plural („1 lună”, „2 luni”, „24 de luni”). Keep the no-break spaces.")
        default:
            return "\(number)\u{00A0}\(label)"
        }
    }

    /// The whole number `value` is, without its sign, when it has no decimals and fits.
    private static func wholeCount(_ value: Double) -> Int? {
        let magnitude = abs(value)
        guard magnitude.rounded() == magnitude, magnitude < Double(Int.max) else { return nil }
        return Int(magnitude)
    }

    /// Every spelling of a catalog unit read as it: the key, the label (also in the app's
    /// language) and what earlier versions wrote, folded (`fold`). Only spellings the app
    /// has written: a unit the person typed another way stays theirs, as written.
    var spellings: Set<String> {
        let earlier: [String] = switch key {
        // Capture wrote "mc" for gas and water; the number reader accepted "m3".
        case "m3": ["m³", "mc", "m3"]
        // The Romanian labels before keys, whatever language the app now speaks.
        case "months": ["luni"]
        case "shots": ["cafele"]
        default: []
        }
        return Set(([key, label] + earlier).map(Self.fold))
    }

    // MARK: Reading

    /// Any stored or typed form: a key, a label, an earlier spelling, or a unit of the
    /// person's own (kept as written, trimmed). Nil for empty text.
    public init?(_ text: String?) {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self = Self.bySpelling[Self.fold(trimmed)] ?? MeasurementUnit(key: trimmed)
    }

    /// Every folded spelling of the catalog's units, worked out once.
    private static let bySpelling: [String: MeasurementUnit] = {
        var table: [String: MeasurementUnit] = [:]
        for unit in catalog {
            for spelling in unit.spellings where table[spelling] == nil { table[spelling] = unit }
        }
        return table
    }()

    /// Lowercase, no diacritics, superscript digits as digits; one character for each, so a
    /// folded text still lines up with what was read.
    static func fold(_ text: String) -> String {
        RomanianText.fold(text)
            .replacingOccurrences(of: "³", with: "3")
            .replacingOccurrences(of: "²", with: "2")
    }

    /// The key to store for text in any form: "" stays "" (no unit).
    public static func storedKey(for text: String) -> String {
        MeasurementUnit(text)?.key ?? ""
    }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        // Codable has no empty unit: an empty one is read as the person's own, "" kept as is.
        self = MeasurementUnit(text) ?? MeasurementUnit(key: text)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(key)
    }
}
