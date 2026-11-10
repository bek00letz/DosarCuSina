import Foundation

/// Reads the machine-readable zone at the bottom of passports and ID cards (ICAO Doc 9303).
///
/// The MRZ is the most reliable thing on an identity document: every important field
/// has a check digit, so a value that passes is exactly what's printed. That's why
/// the passport expiry date can be trusted enough to plan a reminder 9 months out.
///
/// Supports TD3 (passports, 2 × 44), TD2 (older ID cards, including the older
/// Romanian buletin, 2 × 36) and TD1 (current ID cards, 3 × 30). Recognition often
/// confuses OCR-B characters (O/0, I/1/L, B/8, S/5); a field is repaired only when its
/// own check digit proves the repair (see `checked(_:check:as:)`). Two-digit years take
/// the century of the date's plausibility window.
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
        public let birthDate: CalendarDay?
        public let sex: String?
        public let expiryDate: CalendarDay?
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

        /// How many of the four check digits pass, for choosing between readings.
        public var passingChecks: Int {
            [documentNumberValid, birthDateValid, expiryDateValid, compositeValid].filter { $0 }.count
        }
    }

    // MARK: - Public API

    /// Finds and parses an MRZ anywhere in recognized text.
    /// When several readings fit, the one with the most passing check digits wins.
    /// - Parameter referenceDate: "Today", for the windows that decide two-digit years.
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
                if best.map({ result.passingChecks > $0.passingChecks }) ?? true { best = result }
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
        let today = CalendarDay(referenceDate)

        switch format {
        case .td3:
            let (l1, l2) = (rows[0], rows[1])
            guard l1[0] == "P" else { return nil }
            let windows = Windows(kind: .passport, today: today)
            let names = parseNames(String(l1[5..<44]))
            var doc = checked(String(l2[0..<9]), check: l2[9], as: .alphanumeric)
            let birth = checked(String(l2[13..<19]), check: l2[19], as: .numeric)
            let expiry = checked(String(l2[21..<27]), check: l2[27], as: .numeric)
            // Optional data (the CNP on Romanian passports); an all-filler field may carry a filler check.
            let rawOptional = String(l2[28..<42])
            var optional = l2[42] == "<" && rawOptional.allSatisfy { $0 == "<" }
                ? CheckedField(value: rawOptional, check: "<", valid: true, original: rawOptional)
                : checked(rawOptional, check: l2[42], as: .alphanumeric)
            let composite = doc.value + doc.check + birth.value + birth.check + expiry.value + expiry.check + optional.value + String(l2[42])
            let compositeValid = optional.valid && checkDigit(for: composite) == checkValue(l2[43])
            // A repair found by trying swaps must also agree with the composite check digit.
            if !compositeValid { doc = doc.unrepaired; optional = optional.unrepaired }
            return Result(
                format: .td3,
                documentCode: cleanFiller(String(l1[0..<2])),
                issuingCountry: cleanFiller(String(l1[2..<5])),
                documentNumber: cleanFiller(doc.value),
                nationality: cleanFiller(String(l2[10..<13])),
                birthDate: day(fromYYMMDD: birth.value, in: windows.birth),
                sex: sexValue(l2[20]),
                expiryDate: day(fromYYMMDD: expiry.value, in: windows.expiry),
                surname: names.surname,
                givenNames: names.given,
                optionalData: cleanFiller(optional.value),
                documentNumberValid: doc.valid,
                birthDateValid: birth.valid,
                expiryDateValid: expiry.valid,
                compositeValid: compositeValid
            )

        case .td2:
            let (l1, l2) = (rows[0], rows[1])
            guard "IAC".contains(l1[0]) else { return nil }
            let windows = Windows(kind: .identityCard, today: today)
            let names = parseNames(String(l1[5..<36]))
            var doc = checked(String(l2[0..<9]), check: l2[9], as: .alphanumeric)
            let birth = checked(String(l2[13..<19]), check: l2[19], as: .numeric)
            let expiry = checked(String(l2[21..<27]), check: l2[27], as: .numeric)
            let optional = fillers(String(l2[28..<35]))
            let composite = doc.value + doc.check + birth.value + birth.check + expiry.value + expiry.check + optional
            let compositeValid = checkDigit(for: composite) == checkValue(l2[35])
            if !compositeValid { doc = doc.unrepaired }
            return Result(
                format: .td2,
                documentCode: cleanFiller(String(l1[0..<2])),
                issuingCountry: cleanFiller(String(l1[2..<5])),
                documentNumber: cleanFiller(doc.value),
                nationality: cleanFiller(String(l2[10..<13])),
                birthDate: day(fromYYMMDD: birth.value, in: windows.birth),
                sex: sexValue(l2[20]),
                expiryDate: day(fromYYMMDD: expiry.value, in: windows.expiry),
                surname: names.surname,
                givenNames: names.given,
                optionalData: cleanFiller(optional),
                documentNumberValid: doc.valid,
                birthDateValid: birth.valid,
                expiryDateValid: expiry.valid,
                compositeValid: compositeValid
            )

        case .td1:
            let (l1, l2, l3) = (rows[0], rows[1], rows[2])
            guard "IAC".contains(l1[0]) else { return nil }
            let windows = Windows(kind: .identityCard, today: today)
            var upperOptional = fillers(String(l1[15..<30]))
            var document: CheckedField
            let documentPart: (CheckedField, String) -> String
            if l1[14] == "<", let filler = upperOptional.firstIndex(of: "<"), filler > upperOptional.startIndex {
                // Long document numbers continue into the optional data; the last character before the filler is the check digit.
                let extended = String(upperOptional[..<filler])
                let rest = String(upperOptional[filler...])
                document = checked(String(l1[5..<14]) + String(extended.dropLast()), check: extended.last ?? "<", as: .alphanumeric)
                documentPart = { field, _ in String(field.value.prefix(9)) + "<" + String(field.value.dropFirst(9)) + field.check + rest }
                upperOptional = ""
            } else {
                document = checked(String(l1[5..<14]), check: l1[14], as: .alphanumeric)
                documentPart = { field, optional in field.value + field.check + optional }
            }
            let birth = checked(String(l2[0..<6]), check: l2[6], as: .numeric)
            let expiry = checked(String(l2[8..<14]), check: l2[14], as: .numeric)
            let lowerOptional = fillers(String(l2[18..<29]))
            let composite = documentPart(document, upperOptional) + birth.value + birth.check + expiry.value + expiry.check + lowerOptional
            let compositeValid = checkDigit(for: composite) == checkValue(l2[29])
            if !compositeValid { document = document.unrepaired }
            let documentNumber = document.value
            let documentValid = document.valid
            let names = parseNames(String(l3))
            return Result(
                format: .td1,
                documentCode: cleanFiller(String(l1[0..<2])),
                issuingCountry: cleanFiller(String(l1[2..<5])),
                documentNumber: cleanFiller(documentNumber),
                nationality: cleanFiller(String(l2[15..<18])),
                birthDate: day(fromYYMMDD: birth.value, in: windows.birth),
                sex: sexValue(l2[7]),
                expiryDate: day(fromYYMMDD: expiry.value, in: windows.expiry),
                surname: names.surname,
                givenNames: names.given,
                optionalData: cleanFiller(String(documentPart(document, upperOptional).dropFirst(10)) + lowerOptional),
                documentNumberValid: documentValid,
                birthDateValid: birth.valid,
                expiryDateValid: expiry.valid,
                compositeValid: compositeValid
            )
        }
    }

    /// The windows the zone's two-digit years are read in: the same plausibility windows
    /// `CaptureConsistency` checks every identity document's dates against.
    private struct Windows {
        let birth: DateWindow
        let expiry: DateWindow

        init(kind: CaptureDocumentKind, today: CalendarDay) {
            birth = CaptureConsistency.window(for: .birthDate, kind: kind, today: today)
            expiry = CaptureConsistency.window(for: .expiryDate, kind: kind, today: today)
        }
    }

    // MARK: - Check-digit-guided correction

    /// What a field may hold: digits only (dates), or letters and digits (document numbers, optional data).
    enum FieldContent {
        case numeric
        case alphanumeric
    }

    /// OCR-B characters recognition mistakes for one another.
    static let confusions: [[Character]] = [
        ["O", "0", "Q"], ["I", "1", "L"], ["B", "8"], ["S", "5"], ["Z", "2"], ["G", "6"],
    ]

    /// Letters recognition reads where only a digit can stand (a date, a check digit).
    private static let digitLookalikes: [Character: Character] = [
        "O": "0", "Q": "0", "D": "0", "U": "0",
        "I": "1", "L": "1", "T": "1",
        "Z": "2", "S": "5", "B": "8", "G": "6",
    ]

    /// The most characters one field may have swapped before a repair is refused.
    static let maximumRepairs = 2

    /// A field after its check: the value to use, its check character, whether it passed,
    /// and what was read before any swap was tried.
    struct CheckedField: Hashable, Sendable {
        let value: String
        let check: String
        let valid: Bool
        let original: String

        /// Whether the value came from trying swaps, rather than as read.
        var isRepaired: Bool { value != original }

        /// The field as read, unverified, when a tried repair isn't confirmed elsewhere.
        var unrepaired: CheckedField {
            isRepaired ? CheckedField(value: original, check: check, valid: false, original: original) : self
        }
    }

    /// A field checked against its check digit, repaired only where the check digit proves it.
    ///
    /// Where only digits can stand, a look-alike letter can only be its digit. Otherwise,
    /// when the check fails, the common OCR-B swaps (O/0/Q, I/1/L, B/8, S/5, Z/2, G/6, and a
    /// `K` between fillers for `<`) are tried inside this field only, fewest swaps first.
    /// A repair is kept only when exactly one combination at that count passes; two that
    /// pass are a guess, and the field stays as read, unverified. The format then also
    /// asks the composite check digit to agree before it keeps a repair.
    static func checked(_ raw: String, check rawCheck: Character, as content: FieldContent) -> CheckedField {
        let checkCharacter = digitLookalikes[rawCheck] ?? rawCheck
        let check = String(checkCharacter)
        // Where only digits can stand, a look-alike letter can only be its digit: not a guess.
        let field = content == .numeric ? String(raw.map { digitLookalikes[$0] ?? $0 }) : fillers(raw)
        let asRead = CheckedField(value: field, check: check, valid: false, original: field)
        guard let expected = checkValue(checkCharacter) else { return asRead }
        if checkDigit(for: field) == expected { return CheckedField(value: field, check: check, valid: true, original: field) }
        guard content == .alphanumeric else { return asRead }

        let characters = Array(field)
        let choices: [(index: Int, options: [Character])] = characters.indices.compactMap { index in
            let options = alternatives(at: index, in: characters)
            return options.isEmpty ? nil : (index, options)
        }
        guard !choices.isEmpty else { return asRead }
        for count in 1...min(maximumRepairs, choices.count) {
            var passing = Set<String>()
            for picked in combinations(of: choices.count, choosing: count) {
                for attempt in substitutions(characters, choices: picked.map { choices[$0] }) where checkDigit(for: attempt) == expected {
                    passing.insert(attempt)
                }
                if passing.count > 1 { break }
            }
            if passing.count == 1, let repaired = passing.first {
                return CheckedField(value: repaired, check: check, valid: true, original: field)
            }
            if passing.count > 1 { return asRead }
        }
        return asRead
    }

    /// What a character could have been: a filler for a `K` beside a filler, or the others
    /// of its confusion group, but only where it stands out from its neighbours (a letter
    /// beside digits, a digit between letters). A run of digits is never re-guessed: the
    /// composite check digit can't catch a document number swapped for another with the
    /// same check digit, so swaps are tried only where the reading itself looks wrong.
    private static func alternatives(at index: Int, in characters: [Character]) -> [Character] {
        let character = characters[index]
        let neighbours = [index - 1, index + 1].filter(characters.indices.contains).map { characters[$0] }.filter { $0 != "<" }
        if character == "K" {
            return neighbours.count < [index - 1, index + 1].filter(characters.indices.contains).count ? ["<"] : []
        }
        let standsOut = character.isLetter
            ? neighbours.contains(where: \.isNumber)
            : !neighbours.isEmpty && neighbours.allSatisfy(\.isLetter)
        guard standsOut else { return [] }
        return confusions.first { $0.contains(character) }?.filter { $0 != character } ?? []
    }

    /// Every way to pick `count` of `total` positions, in order.
    private static func combinations(of total: Int, choosing count: Int) -> [[Int]] {
        guard count > 0 else { return [[]] }
        guard total >= count else { return [] }
        var result: [[Int]] = []
        func build(_ start: Int, _ current: [Int]) {
            if current.count == count { result.append(current); return }
            for index in start..<total { build(index + 1, current + [index]) }
        }
        build(0, [])
        return result
    }

    /// The field with each picked position swapped, in every combination of its options.
    private static func substitutions(_ characters: [Character], choices: [(index: Int, options: [Character])]) -> [String] {
        var results: [[Character]] = [characters]
        for choice in choices {
            results = results.flatMap { partial in
                choice.options.map { option in
                    var next = partial
                    next[choice.index] = option
                    return next
                }
            }
        }
        return results.map { String($0) }
    }

    /// `«` and a `K` standing among fillers read as fillers, where the zone pads with `<`.
    static func fillers(_ field: String) -> String {
        var characters = Array(field)
        for index in characters.indices where characters[index] == "«" { characters[index] = "<" }
        for index in characters.indices where characters[index] == "K" {
            let before = index > 0 ? characters[index - 1] : nil
            let after = index + 1 < characters.count ? characters[index + 1] : nil
            if before == "<", after == "<" || after == nil { characters[index] = "<" }
        }
        return String(characters)
    }

    // MARK: - Helpers

    private static func characterValue(_ character: Character) -> Int? {
        if character == "<" { return 0 }
        if let number = character.wholeNumberValue, character.isASCII { return number }
        guard let ascii = character.asciiValue, character.isUppercase, character.isLetter else { return nil }
        return Int(ascii) - 55 // A = 10 … Z = 35
    }

    /// A check digit's value; a look-alike letter counts as its digit, a filler as 0.
    private static func checkValue(_ character: Character) -> Int? {
        let resolved = digitLookalikes[character] ?? character
        if resolved == "<" { return 0 }
        return resolved.isASCII ? resolved.wholeNumberValue : nil
    }

    private static func parseNames(_ field: String) -> (surname: String, given: String) {
        let parts = fillers(field).components(separatedBy: "<<")
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

    /// Converts YYMMDD, deciding the century with the date's plausibility window
    /// (`DateWindow.resolve`), so an expiry is never in the 1900s and a birth year
    /// after this year's belongs to the last century.
    private static func day(fromYYMMDD value: String, in window: DateWindow) -> CalendarDay? {
        guard value.count == 6, value.allSatisfy(\.isNumber),
              let yy = Int(value.prefix(2)),
              let mm = Int(value.dropFirst(2).prefix(2)),
              let dd = Int(value.suffix(2)) else { return nil }
        return window.resolve(twoDigitYear: yy, month: mm, day: dd)
    }
}
