import Foundation

/// The outcome of checking what someone typed into a field.
public enum FieldValidation: Hashable, Sendable {
    case empty
    case valid
    /// Something looks off but saving is allowed (a foreign plate, an old VIN).
    case warning(String)
    /// The value is wrong and must be fixed before saving (a mistyped IBAN).
    case invalid(String)

    public var allowsSaving: Bool {
        if case .invalid = self { return false }
        return true
    }

    public var message: String? {
        switch self {
        case .warning(let text), .invalid(let text): return text
        case .empty, .valid: return nil
        }
    }
}

/// Validation, normalization and display for every `FieldType`, in one place.
/// Input controls pass the raw text here; nothing else re-implements these rules.
public enum FieldFormatter {

    // MARK: Normalize

    /// Cleans typed text into the stored form: uppercase plates and VINs, compact IBANs,
    /// `https://` on bare web addresses. Leaves free text alone apart from trimming.
    public static func normalize(_ raw: String, as type: FieldType) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch type {
        case .plate:
            return formatPlate(trimmed) ?? trimmed.uppercased()
        case .vin:
            return trimmed.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        case .microchip:
            return trimmed.filter(\.isNumber)
        case .iban:
            return trimmed.uppercased().filter { $0.isLetter || $0.isNumber }
        case .phone:
            return normalizePhone(trimmed)
        case .email:
            return trimmed.lowercased()
        case .url:
            guard !trimmed.isEmpty else { return trimmed }
            let lower = trimmed.lowercased()
            return lower.hasPrefix("http://") || lower.hasPrefix("https://") ? trimmed : "https://" + trimmed
        default:
            return trimmed
        }
    }

    // MARK: Validate

    public static func validate(_ raw: String, as type: FieldType) -> FieldValidation {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .empty }
        switch type {
        case .plate:
            return formatPlate(text) != nil
                ? .valid
                : .warning(String(localized: "Nu arată ca un număr românesc, de forma B-123-ABC.", comment: "Plate field hint"))
        case .vin:
            let vin = normalize(text, as: .vin)
            let allowed = vin.allSatisfy { ($0.isLetter || $0.isNumber) && !"IOQ".contains($0) && $0.isASCII }
            return vin.count == 17 && allowed
                ? .valid
                : .warning(String(localized: "Seria de șasiu are de obicei 17 caractere, fără I, O sau Q.", comment: "VIN field hint"))
        case .microchip:
            return normalize(text, as: .microchip).count == 15
                ? .valid
                : .warning(String(localized: "Microcipurile au de obicei 15 cifre.", comment: "Microchip field hint"))
        case .iban:
            return isValidIBAN(normalize(text, as: .iban))
                ? .valid
                : .invalid(String(localized: "IBAN-ul nu e corect. Verifică cifrele.", comment: "IBAN field error"))
        case .email:
            let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$"#
            return text.range(of: pattern, options: .regularExpression) != nil
                ? .valid
                : .invalid(String(localized: "Adresa de e-mail nu e completă.", comment: "Email field error"))
        case .url:
            let candidate = normalize(text, as: .url)
            guard let url = URL(string: candidate), let host = url.host(), host.contains(".") else {
                return .invalid(String(localized: "Adresa web nu e completă.", comment: "URL field error"))
            }
            return .valid
        case .phone:
            let digits = normalize(text, as: .phone).filter(\.isNumber)
            return (7...15).contains(digits.count)
                ? .valid
                : .invalid(String(localized: "Numărul de telefon nu e complet.", comment: "Phone field error"))
        case .year:
            let latest = Calendar.current.component(.year, from: Date()) + 1
            guard let year = parseNumber(text), year == year.rounded(), (1900...Double(latest)).contains(year) else {
                return .invalid(String(localized: "Scrie anul cu patru cifre, de exemplu 2018.", comment: "Year field error"))
            }
            return .valid
        case .number, .metric:
            return parseNumber(text) != nil
                ? .valid
                : .invalid(String(localized: "Scrie doar cifre.", comment: "Number field error"))
        case .money:
            return Money.parseAmount(text) != nil
                ? .valid
                : .invalid(String(localized: "Scrie suma în cifre, de exemplu 350 sau 1.250,50.", comment: "Money field error"))
        case .secret:
            return text.allSatisfy(\.isNumber)
                ? .valid
                : .warning(String(localized: "Codurile PIN au de obicei doar cifre.", comment: "Secret PIN field hint"))
        case .text, .longText, .address, .choice, .multiChoice, .date, .expiryDate, .toggle:
            return .valid
        }
    }

    // MARK: Parse

    /// Turns typed text into a stored value, or nil when the text is empty or unreadable.
    /// Dates, toggles and multi-choice come from their own controls, not from text.
    public static func value(from raw: String, as type: FieldType, currency: String = Money.defaultCurrency) -> FieldValue? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        switch type.valueKind {
        case .text:
            return .text(normalize(text, as: type))
        case .number:
            return parseNumber(text).map(FieldValue.number)
        case .money:
            return Money.parseAmount(text).map { .money(Money($0, currency: currency)) }
        case .date:
            return CalendarDay(isoString: text).map(FieldValue.date)
        case .bool, .choices:
            return nil
        }
    }

    public static func parseNumber(_ raw: String) -> Double? {
        Money.parseAmount(raw).map { NSDecimalNumber(decimal: $0).doubleValue }
    }

    // MARK: Display

    /// Human-readable text for a value of `field`. Choice keys show their labels.
    public static func display(_ value: FieldValue, field: FieldDefinition, locale: Locale = .dosarDefault) -> String {
        switch (field.type, value) {
        case (.choice, .text(let key)):
            return field.label(forChoice: key)
        case (.multiChoice, .choices(let keys)):
            return keys.map(field.label(forChoice:)).formatted(.list(type: .and).locale(locale))
        default:
            return display(value, as: field.type, unit: field.unit, locale: locale)
        }
    }

    /// Human-readable text for a stored value, using the field's type and unit.
    public static func display(_ value: FieldValue, as type: FieldType, unit: String? = nil, locale: Locale = .dosarDefault) -> String {
        switch value {
        case .text(let text):
            switch type {
            // A secret never shows through a general path; only `SecretReveal` opens it.
            case .secret: return SecretFields.mask
            case .iban: return groupIBAN(text)
            case .plate: return formatPlate(text) ?? text
            default: return text
            }
        case .number(let number) where type == .year:
            return number.formatted(.number.grouping(.never).precision(.fractionLength(0)).locale(locale))
        case .number(let number):
            let formatted = number.formatted(.number.locale(locale).precision(.fractionLength(0...2)))
            if let unit, !unit.isEmpty { return "\(formatted) \(unit)" }
            return formatted
        case .money(let money):
            return money.formatted(locale: locale)
        case .date(let day):
            return DosarFormat.day(day, locale: locale)
        case .bool(let flag):
            return flag ? String(localized: "Da") : String(localized: "Nu")
        case .choices(let items):
            return items.formatted(.list(type: .and).locale(locale))
        }
    }

    // MARK: Plates

    /// Romanian county codes used on registration plates (`B` is Bucharest).
    public static let countyCodes: Set<String> = [
        "AB", "AR", "AG", "BC", "BH", "BN", "BT", "BV", "BR", "BZ", "CS", "CL", "CJ", "CT", "CV",
        "DB", "DJ", "GL", "GR", "GJ", "HR", "HD", "IL", "IS", "IF", "MM", "MH", "MS", "NT", "OT",
        "PH", "SM", "SJ", "SB", "SV", "TR", "TM", "TL", "VS", "VL", "VN", "B",
    ]

    /// Formats a Romanian plate as `B-123-ABC` / `CJ-12-XYZ`, or nil if it isn't one.
    public static func formatPlate(_ raw: String) -> String? {
        let compact = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        guard compact.allSatisfy(\.isASCII) else { return nil }
        let letters = compact.prefix { $0.isLetter }
        let rest = compact.dropFirst(letters.count)
        let digits = rest.prefix { $0.isNumber }
        let suffix = rest.dropFirst(digits.count)
        let county = String(letters)
        guard countyCodes.contains(county), suffix.count == 3, suffix.allSatisfy(\.isLetter) else { return nil }
        let digitRange = county == "B" ? 2...3 : 2...2
        guard digitRange.contains(digits.count) else { return nil }
        return "\(county)-\(digits)-\(suffix)"
    }

    // MARK: IBAN

    /// ISO 13616 check: moves the first four characters to the end and checks mod 97.
    public static func isValidIBAN(_ raw: String) -> Bool {
        let iban = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        guard (15...34).contains(iban.count), iban.allSatisfy(\.isASCII) else { return false }
        if iban.hasPrefix("RO") && iban.count != 24 { return false }
        let rearranged = iban.dropFirst(4) + iban.prefix(4)
        var remainder = 0
        for character in rearranged {
            let chunk: String
            if let digit = character.wholeNumberValue {
                chunk = String(digit)
            } else if let ascii = character.asciiValue, character.isLetter {
                chunk = String(Int(ascii) - 55)
            } else {
                return false
            }
            for c in chunk {
                remainder = (remainder * 10 + (c.wholeNumberValue ?? 0)) % 97
            }
        }
        return remainder == 1
    }

    public static func groupIBAN(_ raw: String) -> String {
        let compact = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        return stride(from: 0, to: compact.count, by: 4).map { offset -> String in
            let start = compact.index(compact.startIndex, offsetBy: offset)
            let end = compact.index(start, offsetBy: 4, limitedBy: compact.endIndex) ?? compact.endIndex
            return String(compact[start..<end])
        }.joined(separator: " ")
    }

    // MARK: Phone

    /// Keeps a leading `+` and the digits; turns `0040…` into `+40…`.
    public static func normalizePhone(_ raw: String) -> String {
        let hasPlus = raw.hasPrefix("+")
        var digits = raw.filter(\.isNumber)
        if !hasPlus, digits.hasPrefix("00") {
            digits.removeFirst(2)
            return "+" + digits
        }
        return (hasPlus ? "+" : "") + digits
    }
}
