import Foundation

/// What a number is, so the reader knows which rule settles a doubtful case.
public enum NumberKind: Sendable, Hashable, CaseIterable {
    /// An amount of money: decimals allowed.
    case money
    /// Something counted: whole numbers only.
    case count
    /// A meter index or another measured value (a weight): decimals allowed.
    case meterIndex
    /// A kilometre reading: whole numbers only.
    case kilometres

    /// Kilometres and counts have no decimals, so "45,724 km" can only be 45724.
    public var isWhole: Bool { self == .count || self == .kilometres }

    /// The kind of a typed field's number: kilometres by their unit, whole numbers
    /// when the field shows no decimals (a year), any other measured value otherwise.
    public static func forField(unit: MeasurementUnit?, allowsDecimals: Bool = true) -> NumberKind {
        if unit == .kilometres { return .kilometres }
        return allowsDecimals ? .meterIndex : .count
    }
}

/// Where a number comes from. A document's number that could be read two ways is
/// marked "Verifică"; what the person typed is shown back to them as it was read.
public enum NumberOrigin: Sendable, Hashable {
    case typed
    case document
}

/// The one reader for numbers written by people and printed on Romanian documents,
/// used by every capture reader and every number field. The rule, the owner's:
///
/// - a comma is the decimal mark and a dot groups thousands: "1.250,50" is 1250.5;
/// - a number with both marks takes the last one as the decimal mark ("1,250.50" too);
/// - kilometres and counts are whole, so any single mark followed by three digits groups
///   thousands: "45,724 km" and "45.724 km" are both 45724;
/// - a money amount or a meter index with one mark and exactly three digits after it
///   follows the Romanian rule ("3,750" is 3,75 and "45.724" is 45724) and is ambiguous:
///   from a document it gets "Verifică";
/// - anything it can't read clearly ("-", ".", "12-5", "5²", "12 km" for money) is
///   refused with a message for the field, never read as 0 or cut short.
///
/// Archives and stored JSON use the machine form ("1250.5"), read with `canonical`.
public enum RomanianNumber {
    /// The locale numbers, money and dates are written in, whatever the phone's region or
    /// number format: what the app writes is what this reader reads back.
    public static var locale: Locale { .dosarDefault }

    /// A number read clearly.
    public struct Reading: Hashable, Sendable {
        public let value: Decimal
        /// One mark followed by three digits on money or a meter index: the Romanian rule
        /// decided, but a document from elsewhere could have meant the other reading.
        public let isAmbiguous: Bool
        /// A document's ambiguous number: shown with "Verifică".
        public let needsCheck: Bool

        public var doubleValue: Double { NSDecimalNumber(decimal: value).doubleValue }
    }

    /// Why a text isn't a number of the kind asked for.
    public enum Problem: Error, Hashable, Sendable {
        /// Nothing written.
        case empty
        /// Not a number that can be read one way only.
        case unreadable
        /// Below zero.
        case negative
        /// Decimals where the kind is whole (kilometres, counts).
        case notWhole

        /// What to tell the person in the field, for this kind of number.
        public func message(for kind: NumberKind) -> String {
            switch (self, kind) {
            case (.negative, .money):
                return String(localized: "Suma nu poate fi negativă.", comment: "Number field error: a money amount below zero.")
            case (.negative, _):
                return String(localized: "Numărul nu poate fi negativ.", comment: "Number field error: a reading or count below zero.")
            case (.notWhole, .kilometres):
                return String(localized: "Scrie kilometrii fără zecimale.", comment: "Number field error: kilometres with decimals.")
            case (.notWhole, _):
                return String(localized: "Scrie un număr întreg, fără zecimale.", comment: "Number field error: a count with decimals.")
            case (_, .money):
                return String(localized: "Scrie suma doar cu cifre, de exemplu 1.250,50.", comment: "Number field error: a money amount that can't be read.")
            case (_, .kilometres):
                return String(localized: "Scrie kilometrii doar cu cifre, de exemplu 84.200.", comment: "Number field error: kilometres that can't be read.")
            case (_, .meterIndex):
                return String(localized: "Scrie doar cifre, de exemplu 12.345 sau 4,5.", comment: "Number field error: a meter index or measured value that can't be read.")
            case (_, .count):
                return String(localized: "Scrie doar cifre, de exemplu 12.", comment: "Number field error: a count that can't be read.")
            }
        }
    }

    // MARK: Reading

    /// Reads `raw` as a number of `kind`. A label before a colon ("Index nou: 12.345") and
    /// the kind's unit after the number ("86.420 km", "350 lei", or `unit`) are allowed.
    public static func read(_ raw: String, as kind: NumberKind, from origin: NumberOrigin = .typed, unit: MeasurementUnit? = nil) -> Result<Reading, Problem> {
        var text = raw
        for space in ["\u{00A0}", "\u{202F}", "\u{2009}", "\t"] { text = text.replacingOccurrences(of: space, with: " ") }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failure(.empty) }
        text = droppingLabel(text)
        text = droppingUnit(text, kind: kind, unit: unit)
        guard !text.isEmpty else { return .failure(.unreadable) }

        var negative = false
        if let first = text.first, first == "-" || first == "−" {
            negative = true
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        guard let parsed = digits(text, kind: kind) else { return .failure(.unreadable) }
        guard !negative || parsed.value == 0 else { return .failure(.negative) }
        if kind.isWhole, parsed.value != parsed.value.rounded(scale: 0) { return .failure(.notWhole) }
        return .success(Reading(value: parsed.value, isAmbiguous: parsed.ambiguous, needsCheck: parsed.ambiguous && origin == .document))
    }

    /// The value of `raw`, or nil when it isn't clearly a number of `kind`.
    public static func value(_ raw: String, as kind: NumberKind, from origin: NumberOrigin = .typed, unit: MeasurementUnit? = nil) -> Decimal? {
        try? read(raw, as: kind, from: origin, unit: unit).get().value
    }

    /// Reads the plain machine form archives and stored JSON use: "1250.5", "-3", "45724".
    public static func canonical(_ raw: String) -> Decimal? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard TextPattern.first(#"^-?\d+(\.\d+)?$"#, in: text) != nil else { return nil }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    // MARK: Writing

    /// How a number reads in a field or on screen, the Romanian way: "45.724", "1.250,5".
    /// What this writes, `read` reads back to the same value.
    public static func format(_ value: Decimal, fractionDigits: ClosedRange<Int> = 0...2, groupsDigits: Bool = true) -> String {
        value.formatted(.number.precision(.fractionLength(fractionDigits)).grouping(groupsDigits ? .automatic : .never).locale(locale))
    }

    // MARK: Pieces

    /// "Index nou: 12.345" → "12.345". Only a label without digits is dropped, so "12:30" stays unreadable.
    private static func droppingLabel(_ text: String) -> String {
        guard let colon = text.lastIndex(of: ":") else { return text }
        let label = text[..<colon]
        guard !label.contains(where: \.isNumber), label.contains(where: \.isLetter) else { return text }
        return text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    }

    /// Units a kind may carry after its number, folded (`MeasurementUnit.fold`). Measured
    /// units come from the unit catalog, in every spelling it reads.
    private static func units(for kind: NumberKind) -> [String] {
        switch kind {
        case .money: return ["lei", "leu", "ron", "eur", "euro", "€", "usd", "$"]
        case .kilometres: return Array(MeasurementUnit.kilometres.spellings)
        case .meterIndex: return MeasurementUnit.meterUnits.flatMap(\.spellings)
        case .count: return []
        }
    }

    private static func droppingUnit(_ text: String, kind: NumberKind, unit: MeasurementUnit?) -> String {
        let folded = MeasurementUnit.fold(text)
        let candidates = (units(for: kind) + (unit.map { Array($0.spellings) } ?? []))
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
        for candidate in candidates where folded.hasSuffix(candidate) {
            let kept = String(text.dropLast(candidate.count)).trimmingCharacters(in: .whitespaces)
            // "12km" and "12 km" both drop the unit; "kkm" never leaves letters behind.
            guard kept.last.map({ !$0.isLetter }) ?? true else { continue }
            return kept
        }
        return text
    }

    /// Digits with dots, commas or spaces between them, read by the rule above.
    private static func digits(_ text: String, kind: NumberKind) -> (value: Decimal, ambiguous: Bool)? {
        guard TextPattern.first(#"^\d+([., ]\d+)*$"#, in: text) != nil else { return nil }
        var groups: [String] = []
        var marks: [Character] = []
        var current = ""
        for character in text {
            if character.isNumber {
                current.append(character)
            } else {
                groups.append(current)
                marks.append(character)
                current = ""
            }
        }
        groups.append(current)

        // Thousands groups: the first of one to three digits, every other of exactly three.
        func groupsThousands(_ parts: ArraySlice<String>) -> Bool {
            guard let first = parts.first, (1...3).contains(first.count) else { return false }
            if parts.count > 1, first.hasPrefix("0") { return false }
            return parts.dropFirst().allSatisfy { $0.count == 3 }
        }
        func number(whole: ArraySlice<String>, fraction: String?) -> Decimal? {
            let plain = whole.joined() + (fraction.map { "." + $0 } ?? "")
            return Decimal(string: plain, locale: Locale(identifier: "en_US_POSIX"))
        }

        guard !marks.isEmpty else { return number(whole: groups[...], fraction: nil).map { ($0, false) } }

        let distinct = Set(marks.filter { $0 != " " })
        let last = marks[marks.count - 1]
        switch distinct.count {
        case 0:
            // Spaces only: "1 250 000".
            return groupsThousands(groups[...]) ? number(whole: groups[...], fraction: nil).map { ($0, false) } : nil
        case 2:
            // "1.250,50" or "1,250.50": the last mark is the decimal one, once, after groups.
            guard last != " ", marks.filter({ $0 == last }).count == 1,
                  groupsThousands(groups.dropLast()) else { return nil }
            return number(whole: groups.dropLast(), fraction: groups.last).map { ($0, false) }
        default:
            let mark = distinct.first!
            let count = marks.filter { $0 == mark }.count
            if count > 1 {
                // "1.250.500": only thousands.
                return groupsThousands(groups[...]) ? number(whole: groups[...], fraction: nil).map { ($0, false) } : nil
            }
            // One dot or comma, maybe after space groups ("1 250,50"). It has to be the last mark.
            guard last == mark else { return nil }
            let before = groups.dropLast()
            let after = groups[groups.count - 1]
            let canGroup = after.count == 3 && groupsThousands(groups[...])
            let canBeDecimal = before.count == 1 || groupsThousands(before)
            if canGroup && kind.isWhole {
                return number(whole: groups[...], fraction: nil).map { ($0, false) }
            }
            if canGroup && canBeDecimal {
                // The doubtful case: the Romanian rule decides, and says so.
                return mark == ","
                    ? number(whole: before, fraction: after).map { ($0, true) }
                    : number(whole: groups[...], fraction: nil).map { ($0, true) }
            }
            if canGroup { return number(whole: groups[...], fraction: nil).map { ($0, false) } }
            guard canBeDecimal else { return nil }
            return number(whole: before, fraction: after).map { ($0, false) }
        }
    }
}
