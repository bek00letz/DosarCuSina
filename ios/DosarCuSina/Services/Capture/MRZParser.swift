import Foundation

/// Reads the machine-readable zone at the bottom of passports and ID cards (ICAO Doc 9303).
///
/// The MRZ is the most reliable thing on an identity document: every important field
/// has a check digit, so a value that passes is exactly what's printed. That's why
/// the passport expiry date can be trusted enough to plan a reminder 9 months out.
///
/// Supports TD3 (passports, 2 × 44), TD2 (older ID cards, including the older
/// Romanian buletin, 2 × 36) and TD1 (current ID cards, 3 × 30). OCR often confuses
/// letters and digits (O/0, I/1, S/5, B/8); numeric fields are repaired only when the
/// repair makes the check digit pass.
public enum MRZParser {

    public enum Format: String, Codable, Sendable {
        case td1, td2, td3

        var lineLength: Int {
            switch self {
            case .td1: 30
            case .td2: 36
            case .td3: 44
            }
        }

        var lineCount: Int { self == .td1 ? 3 : 2 }
    }

    public struct Result: Hashable, Sendable {
        public let format: Format
        /// `P` for passports, `I`, `A` or `C` for ID cards. A second letter may follow.
        public let documentCode: String
        public let issuingCountry: String
        public let documentNumber: String
        public let nationality: String
        public let birthDate: CaptureDay?
        public let sex: String?
        public let expiryDate: CaptureDay?
        public let surname: String
        public let givenNames: String
        /// Optional data. On Romanian passports this holds the personal numeric code.
        public let optionalData: String
        public let documentNumberValid: Bool
        public let birthDateValid: Bool
        public let expiryDateValid: Bool
        public let compositeValid: Bool

        public var allChecksValid: Bool {
            documentNumberValid && birthDateValid && expiryDateValid && compositeValid
        }

        public var isPassport: Bool { documentCode.hasPrefix("P") }
    }

    // MARK: - Public API

    /// Finds and parses an MRZ anywhere in recognized text.
    /// - Parameter referenceDate: Used to decide the century of two-digit birth years.
    public static func parse(text: String, referenceDate: Date = Date()) -> Result? {
        let candidates = candidateLines(in: text)
        var best: Result?
        for format in [Format.td3, .td1, .td2] {
            let lines = candidates.compactMap { fit($0, to: format.lineLength) }
            guard lines.count >= format.lineCount else { continue }
            for start in 0...(lines.count - format.lineCount) {
                let window = Array(lines[start..<(start + format.lineCount)])
                guard let result = parse(lines: window, format: format, referenceDate: referenceDate) else { continue }
                if result.allChecksValid { return result }
                if best == nil { best = result }
            }
        }
        return best
    }

    /// The ICAO 9303 check digit for a field (weights 7, 3, 1; `<` counts as 0).
    public static func checkDigit(for field: some StringProtocol) -> Int? {
        let weights = [7, 3, 1]
        var sum = 0
        for (index, character) in field.enumerated() {
            guard let value = characterValue(character) else { return nil }
            sum += value * weights[index % 3]
        }
        return sum % 10
    }

    // MARK: - Line detection

    /// Lines that look like MRZ text after removing spaces and common OCR artifacts.
    static func candidateLines(in text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { line in
                line.uppercased()
                    .replacingOccurrences(of: "«", with: "<<")
                    .replacingOccurrences(of: "‹", with: "<")
                    .filter { !$0.isWhitespace }
            }
            .filter { line in
                line.count >= 28 && line.count <= 46
                    && line.contains("<")
                    && line.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "<") }
            }
    }

    /// Pads short lines with fillers and trims trailing fillers from long ones, so
    /// a line that OCR read one character short or long can still be used.
    static func fit(_ line: String, to length: Int) -> String? {
        if line.count == length { return line }
        if line.count < length, length - line.count <= 2 {
            return line + String(repeating: "<", count: length - line.count)
        }
        if line.count > length, line.count - length <= 2 {
            let trimmed = line.dropLast(line.count - length)
            let removed = line.suffix(line.count - length)
            return removed.allSatisfy { $0 == "<" } ? String(trimmed) : nil
        }
        return nil
    }

    // MARK: - Formats

    static func parse(lines: [String], format: Format, referenceDate: Date) -> Result? {
        let rows = lines.map { Array($0) }
        guard rows.allSatisfy({ $0.count == format.lineLength }) else { return nil }

        switch format {
        case .td3:
            let (l1, l2) = (rows[0], rows[1])
            guard l1[0] == "P" else { return nil }
            let names = parseNames(String(l1[5..<44]))
            let doc = repairNumeric(String(l2[0..<9]), check: l2[9], allowLetters: true)
            let birth = repairNumeric(String(l2[13..<19]), check: l2[19])
            let expiry = repairNumeric(String(l2[21..<27]), check: l2[27])
            let optional = String(l2[28..<42])
            let optionalValid = l2[42] == "<" ? optional.allSatisfy { $0 == "<" } : checkDigit(for: optional) == digit(l2[42])
            let composite = doc.value + String(l2[9]) + birth.value + String(l2[19]) + expiry.value + String(l2[27]) + optional + String(l2[42])
            return Result(
                format: .td3,
                documentCode: cleanFiller(String(l1[0..<2])),
                issuingCountry: cleanFiller(String(l1[2..<5])),
                documentNumber: cleanFiller(doc.value),
                nationality: cleanFiller(String(l2[10..<13])),
                birthDate: day(fromYYMMDD: birth.value, isExpiry: false, referenceDate: referenceDate),
                sex: sexValue(l2[20]),
                expiryDate: day(fromYYMMDD: expiry.value, isExpiry: true, referenceDate: referenceDate),
                surname: names.surname,
                givenNames: names.given,
                optionalData: cleanFiller(optional),
                documentNumberValid: doc.valid,
                birthDateValid: birth.valid,
                expiryDateValid: expiry.valid,
                compositeValid: optionalValid && checkDigit(for: composite) == digit(l2[43])
            )

        case .td2:
            let (l1, l2) = (rows[0], rows[1])
            guard "IAC".contains(l1[0]) else { return nil }
            let names = parseNames(String(l1[5..<36]))
            let doc = repairNumeric(String(l2[0..<9]), check: l2[9], allowLetters: true)
            let birth = repairNumeric(String(l2[13..<19]), check: l2[19])
            let expiry = repairNumeric(String(l2[21..<27]), check: l2[27])
            let optional = String(l2[28..<35])
            let composite = doc.value + String(l2[9]) + birth.value + String(l2[19]) + expiry.value + String(l2[27]) + optional
            return Result(
                format: .td2,
                documentCode: cleanFiller(String(l1[0..<2])),
                issuingCountry: cleanFiller(String(l1[2..<5])),
                documentNumber: cleanFiller(doc.value),
                nationality: cleanFiller(String(l2[10..<13])),
                birthDate: day(fromYYMMDD: birth.value, isExpiry: false, referenceDate: referenceDate),
                sex: sexValue(l2[20]),
                expiryDate: day(fromYYMMDD: expiry.value, isExpiry: true, referenceDate: referenceDate),
                surname: names.surname,
                givenNames: names.given,
                optionalData: cleanFiller(optional),
                documentNumberValid: doc.valid,
                birthDateValid: birth.valid,
                expiryDateValid: expiry.valid,
                compositeValid: checkDigit(for: composite) == digit(l2[35])
            )

        case .td1:
            let (l1, l2, l3) = (rows[0], rows[1], rows[2])
            guard "IAC".contains(l1[0]) else { return nil }
            var documentNumber: String
            var documentValid: Bool
            let optional1 = String(l1[15..<30])
            if l1[14] == "<", let filler = optional1.firstIndex(of: "<"), filler > optional1.startIndex {
                // Long document numbers continue into the optional data; the last digit before the filler is the check digit.
                let extended = String(optional1[..<filler])
                documentNumber = String(l1[5..<14]) + String(extended.dropLast())
                documentValid = checkDigit(for: documentNumber) == extended.last.flatMap(digit)
            } else {
                let repaired = repairNumeric(String(l1[5..<14]), check: l1[14], allowLetters: true)
                documentNumber = repaired.value
                documentValid = repaired.valid
            }
            let birth = repairNumeric(String(l2[0..<6]), check: l2[6])
            let expiry = repairNumeric(String(l2[8..<14]), check: l2[14])
            let optional2 = String(l2[18..<29])
            let composite = String(l1[5..<30]) + birth.value + String(l2[6]) + expiry.value + String(l2[14]) + optional2
            let names = parseNames(String(l3))
            return Result(
                format: .td1,
                documentCode: cleanFiller(String(l1[0..<2])),
                issuingCountry: cleanFiller(String(l1[2..<5])),
                documentNumber: cleanFiller(documentNumber),
                nationality: cleanFiller(String(l2[15..<18])),
                birthDate: day(fromYYMMDD: birth.value, isExpiry: false, referenceDate: referenceDate),
                sex: sexValue(l2[7]),
                expiryDate: day(fromYYMMDD: expiry.value, isExpiry: true, referenceDate: referenceDate),
                surname: names.surname,
                givenNames: names.given,
                optionalData: cleanFiller(optional1 + optional2),
                documentNumberValid: documentValid,
                birthDateValid: birth.valid,
                expiryDateValid: expiry.valid,
                compositeValid: checkDigit(for: composite) == digit(l2[29])
            )
        }
    }

    // MARK: - Helpers

    private static func characterValue(_ character: Character) -> Int? {
        if character == "<" { return 0 }
        if let number = character.wholeNumberValue, character.isASCII { return number }
        guard let ascii = character.asciiValue, character.isUppercase, character.isLetter else { return nil }
        return Int(ascii) - 55 // A = 10 … Z = 35
    }

    private static func digit(_ character: Character) -> Int? {
        character.isASCII ? character.wholeNumberValue : nil
    }

    /// Letters OCR commonly reads in place of digits.
    private static let digitLookalikes: [Character: Character] = [
        "O": "0", "Q": "0", "D": "0", "U": "0",
        "I": "1", "L": "1", "T": "1",
        "Z": "2", "S": "5", "B": "8", "G": "6",
    ]

    /// Validates a field against its check digit. If it fails, tries replacing
    /// look-alike letters with digits (and the check character itself), and keeps
    /// the repair only when the check digit then passes.
    private static func repairNumeric(_ field: String, check: Character, allowLetters: Bool = false) -> (value: String, valid: Bool) {
        let checkValue = digit(check) ?? digitLookalikes[check].flatMap(digit)
        if let checkValue, checkDigit(for: field) == checkValue { return (field, true) }

        let repaired = String(field.map { character in
            allowLetters ? character : (digitLookalikes[character] ?? character)
        })
        if !allowLetters, let checkValue, checkDigit(for: repaired) == checkValue { return (repaired, true) }

        if allowLetters, let checkValue {
            // Document numbers can mix letters and digits; try one substitution at a time.
            let characters = Array(field)
            for index in characters.indices {
                guard let replacement = digitLookalikes[characters[index]] else { continue }
                var attempt = characters
                attempt[index] = replacement
                if checkDigit(for: String(attempt)) == checkValue { return (String(attempt), true) }
            }
        }
        return (allowLetters ? field : repaired, false)
    }

    private static func parseNames(_ field: String) -> (surname: String, given: String) {
        let parts = field.components(separatedBy: "<<")
        let surname = parts.first.map(cleanFiller) ?? ""
        let given = parts.dropFirst().joined(separator: " ")
        return (surname, cleanFiller(given))
    }

    private static func cleanFiller(_ text: String) -> String {
        text.replacingOccurrences(of: "<", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
    }

    private static func sexValue(_ character: Character) -> String? {
        switch character {
        case "M", "F": String(character)
        default: nil
        }
    }

    /// Converts YYMMDD. An expiry more than 50 years ahead belongs to the previous century;
    /// a birth year greater than the current two-digit year belongs to the 1900s.
    private static func day(fromYYMMDD value: String, isExpiry: Bool, referenceDate: Date) -> CaptureDay? {
        guard value.count == 6, value.allSatisfy(\.isNumber),
              let yy = Int(value.prefix(2)),
              let mm = Int(value.dropFirst(2).prefix(2)),
              let dd = Int(value.suffix(2)) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let currentYear = calendar.component(.year, from: referenceDate)
        let currentYY = currentYear % 100
        let century = currentYear - currentYY
        let year: Int
        if isExpiry {
            year = yy + century > currentYear + 50 ? yy + century - 100 : yy + century
        } else {
            year = yy > currentYY ? yy + century - 100 : yy + century
        }
        return CaptureDay(year: year, month: mm, day: dd)
    }
}
