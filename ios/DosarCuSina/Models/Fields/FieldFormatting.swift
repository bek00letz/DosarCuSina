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
            return RomanianText.compact(trimmed)
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
            let latest = Calendar.dosar.component(.year, from: Date()) + 1
            guard let year = RomanianNumber.value(text, as: .count).map({ NSDecimalNumber(decimal: $0).doubleValue }), (1900...Double(latest)).contains(year) else {
                return .invalid(String(localized: "Scrie anul cu patru cifre, de exemplu 2018.", comment: "Year field error"))
            }
            return .valid
        case .number, .metric:
            return validation(of: text, as: .meterIndex)
        case .money:
            return validation(of: text, as: .money)
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
    /// `unit` is the field's unit: kilometres are read as whole numbers.
    public static func value(from raw: String, as type: FieldType, currency: String = Money.defaultCurrency, unit: MeasurementUnit? = nil) -> FieldValue? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        switch type.valueKind {
        case .text:
            return .text(normalize(text, as: type))
        case .number:
            let kind = type == .year ? NumberKind.count : NumberKind.forField(unit: unit)
            return RomanianNumber.value(text, as: kind, unit: unit).map { .number(NSDecimalNumber(decimal: $0).doubleValue) }
        case .money:
            return RomanianNumber.value(text, as: .money).map { .money(Money($0, currency: currency)) }
        case .date:
            return CalendarDay(isoString: text).map(FieldValue.date)
        case .bool, .choices:
            return nil
        }
    }

    public static func parseNumber(_ raw: String) -> Double? {
        RomanianNumber.value(raw, as: .meterIndex).map { NSDecimalNumber(decimal: $0).doubleValue }
    }

    /// The one reader's answer as a field validation: its message when it refuses.
    private static func validation(of text: String, as kind: NumberKind) -> FieldValidation {
        switch RomanianNumber.read(text, as: kind) {
        case .success: return .valid
        case .failure(.empty): return .empty
        case .failure(let problem): return .invalid(problem.message(for: kind))
        }
    }

    // MARK: Display

    /// Human-readable text for a value of `field`. Choice keys show their labels.
    public static func display(_ value: FieldValue, field: FieldDefinition, locale: Locale = .dosarDefault) -> String {
        if SecretFields.isSealed(value) { return SecretFields.mask }
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
    public static func display(_ value: FieldValue, as type: FieldType, unit: MeasurementUnit? = nil, locale: Locale = .dosarDefault) -> String {
        switch value {
        case _ where SecretFields.isSealed(value):
            // Sealed text is a secret whatever the field's type says.
            return SecretFields.mask
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
            if let unit { return "\(formatted) \(unit.label)" }
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
        let compact = RomanianText.compact(raw)
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

    /// How many characters an IBAN has in each country that issues them, as the ISO 13616
    /// registry lists them. A country not listed is checked by its check digits alone.
    public static let ibanLengths: [String: Int] = [
        "AD": 24, "AE": 23, "AL": 28, "AT": 20, "AZ": 28, "BA": 20, "BE": 16, "BG": 22, "BH": 22, "BR": 29,
        "BY": 28, "CH": 21, "CR": 22, "CY": 28, "CZ": 24, "DE": 22, "DJ": 27, "DK": 18, "DO": 28, "EE": 20,
        "EG": 29, "ES": 24, "FI": 18, "FK": 18, "FO": 18, "FR": 27, "GB": 22, "GE": 22, "GI": 23, "GL": 18,
        "GR": 27, "GT": 28, "HR": 21, "HU": 28, "IE": 22, "IL": 23, "IQ": 23, "IS": 26, "IT": 27, "JO": 30,
        "KW": 30, "KZ": 20, "LB": 28, "LC": 32, "LI": 21, "LT": 20, "LU": 20, "LV": 21, "LY": 25, "MC": 27,
        "MD": 24, "ME": 22, "MK": 19, "MN": 20, "MR": 27, "MT": 31, "MU": 30, "NL": 18, "NO": 15, "OM": 23,
        "PK": 24, "PL": 28, "PS": 29, "PT": 25, "QA": 29, "RO": 24, "RS": 22, "RU": 33, "SA": 24, "SC": 31,
        "SD": 18, "SE": 24, "SI": 19, "SK": 24, "SM": 27, "SO": 23, "ST": 25, "SV": 28, "TL": 23, "TN": 24,
        "TR": 26, "UA": 29, "VA": 22, "VG": 24, "XK": 20, "YE": 30,
    ]

    /// ISO 13616 check: two letters for the country, two check digits, the country's length
    /// (`ibanLengths`), then the first four characters moved to the end and checked mod 97.
    public static func isValidIBAN(_ raw: String) -> Bool {
        let iban = RomanianText.compact(raw)
        guard (15...34).contains(iban.count), iban.allSatisfy(\.isASCII) else { return false }
        let head = Array(iban.prefix(4))
        guard head[0].isLetter, head[1].isLetter, head[2].isNumber, head[3].isNumber else { return false }
        if let length = ibanLengths[String(iban.prefix(2))], iban.count != length { return false }
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

    /// Where the text holds an IBAN that passes its check (`isValidIBAN`), however its groups
    /// are spaced: in one piece, in groups of four, with a space or a dash between any of its
    /// characters after the first four. It starts a word with a listed country's letters and
    /// its two check digits ("RO49"), and is taken at that country's length (`ibanLengths`), so
    /// a word that happens to be two letters ("de", "cu") never starts one.
    public static func ibanRanges(in text: String) -> [Range<String.Index>] {
        let positions = Array(text.indices)
        func character(_ offset: Int) -> Character? {
            offset >= 0 && offset < positions.count ? text[positions[offset]] : nil
        }
        func isWordCharacter(_ offset: Int) -> Bool {
            character(offset).map { $0.isLetter || $0.isNumber } ?? false
        }
        func isCode(_ offset: Int) -> Bool {
            character(offset).map { $0.isASCII && ($0.isLetter || $0.isNumber) } ?? false
        }
        func isSeparator(_ offset: Int) -> Bool {
            character(offset).map { $0 == " " || $0 == "-" } ?? false
        }
        // The offset just after the IBAN that starts at `start`, if one does.
        func end(from start: Int) -> Int? {
            guard let first = character(start), let second = character(start + 1),
                  let length = ibanLengths[String([first, second]).uppercased()],
                  let check = character(start + 2), let checkEnd = character(start + 3),
                  check.isASCII, check.isNumber, checkEnd.isASCII, checkEnd.isNumber else { return nil }
            var compact = ""
            var offset = start
            while compact.count < length {
                if isCode(offset) {
                    compact.append(text[positions[offset]])
                    offset += 1
                } else if compact.count >= 4, isSeparator(offset), isCode(offset + 1) {
                    offset += 1
                } else {
                    break
                }
            }
            guard compact.count == length, !isWordCharacter(offset), isValidIBAN(compact) else { return nil }
            return offset
        }
        var found: [Range<String.Index>] = []
        var start = 0
        while start + 1 < positions.count {
            let startsWord = !isWordCharacter(start - 1) && isCode(start) && text[positions[start]].isLetter
            if startsWord, let after = end(from: start) {
                found.append(positions[start]..<(after < positions.count ? positions[after] : text.endIndex))
                start = after
            } else {
                start += 1
            }
        }
        return found
    }

    public static func groupIBAN(_ raw: String) -> String {
        let compact = RomanianText.compact(raw)
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
