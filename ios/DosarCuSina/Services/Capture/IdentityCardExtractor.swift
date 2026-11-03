import Foundation

/// Reads an identity document with its template (`IdentityTemplates`): each field at
/// its printed label (column-aware, through `LabelledLayout`), else in its usual
/// region, else anywhere when its format can't be mistaken, then checked against
/// its format and against the other values.
///
/// Confidence comes from those checks, not from guesses:
/// - a CNP with a valid control digit is certain, and so are the birth date and sex it encodes;
/// - a value read at its label that passes its format is trusted (no "Verifică");
/// - a value found only in a region, or that fails its format, is marked for a check;
/// - two sources agreeing (printed and CNP, printed and MRZ) raise confidence.
///
/// Every date must sit at its own label, so a birth date is never an issue or expiry date.
enum IdentityDocumentReader {

    /// Confidence for a value read at its label that passed its format.
    static let labelled = 0.8
    /// Confidence for a value found by its format anywhere on the page.
    static let anywhere = 0.7
    /// Confidence for a value found only in its usual region.
    static let regional = 0.55
    /// Confidence for a value that failed its format check.
    static let failedFormat = 0.45

    /// - Parameter today: Decides the century of two-digit years, through each date's window.
    static func read(_ text: CaptureText, template: IdentityTemplate, today: CaptureDay) -> [CaptureField] {
        let layout = LabelledLayout(text: text, labels: template.labelTable)
        func window(_ key: CaptureFieldKey) -> DateWindow { CaptureConsistency.window(for: key, kind: template.kind, today: today) }
        var fields: [CaptureField] = []
        func add(_ key: CaptureFieldKey, _ value: CaptureValue, _ confidence: Double, _ source: String?, tier: CaptureTier = .heuristic) {
            guard !fields.contains(where: { $0.key == key }) else { return }
            fields.append(CaptureField(key: key, value: value, confidence: confidence, sourceText: source, tier: tier))
        }

        for field in template.fields {
            let key = IdentityLabelKey.field(field.key)
            if case .dateRange(let startKey) = field.format {
                if let range = dateRange(at: layout.found(for: key), start: window(startKey), end: window(field.key)) {
                    add(field.key, .day(range.end), labelled, range.source)
                    add(startKey, .day(range.start), labelled, range.source)
                }
                continue
            }
            if case .date = field.format {
                // A date only counts at its own label, so a neighbour's date is never borrowed.
                if let (day, source) = layout.day(for: key, window: window(field.key)) {
                    add(field.key, .day(day), labelled, source)
                    continue
                }
            } else if case .categories = field.format {
                // Categories are printed in boxes along the label's row, each its own fragment.
                if let found = layout.restOfRow(for: key) ?? layout.value(for: key), let parsed = parse(found.value, as: .categories) {
                    add(field.key, parsed.value, labelled, found.source)
                    continue
                }
            } else if let found = layout.found(for: key), let parsed = parse(found.value, as: field.format, window: window(field.key)) {
                add(field.key, parsed.value, parsed.passed ? labelled : failedFormat, found.source, tier: parsed.tier)
                continue
            }
            if let region = field.region, let found = inRegion(region, of: text, format: field.format, window: window(field.key)) {
                add(field.key, found.value, regional, found.source)
                continue
            }
            if field.searchesEverywhere, let found = anywhere(in: text, format: field.format, window: window(field.key)) {
                add(field.key, found.value, found.confidence, found.source, tier: found.tier)
            }
        }

        crossCheckPersonalNumber(&fields)
        if let surname = fields.first(where: { $0.key == .surname }) ?? fields.first(where: { $0.key == .givenNames }) {
            let full = [fields.first { $0.key == .givenNames }?.value.text, fields.first { $0.key == .surname }?.value.text]
                .compactMap { $0 }.joined(separator: " ")
            add(.holderName, .text(full), surname.confidence, nil, tier: surname.tier)
        }
        return fields
    }

    // MARK: - Formats

    /// The EU driving licence categories, plus the national tractor and tram ones.
    static let drivingCategories: Set<String> = [
        "AM", "A1", "A2", "A", "B1", "B", "BE", "C1", "C1E", "C", "CE", "D1", "D1E", "D", "DE", "TR", "TB", "TV",
    ]

    struct Parsed {
        let value: CaptureValue
        let passed: Bool
        var tier: CaptureTier = .heuristic
    }

    /// The value in its format, or nil when there is nothing of that shape at all.
    static func parse(_ raw: String, as format: IdentityFormat, window: DateWindow = .aroundToday) -> Parsed? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        switch format {
        case .name:
            return RomanianFieldExtractor.personName(value).map { Parsed(value: .text($0), passed: true) }
        case .personalNumber:
            let digits = value.filter { !$0.isWhitespace }
            guard let match = TextPattern.first(#"(?<!\d)(\d{13})(?!\d)"#, in: digits), let cnp = match[1] else { return nil }
            let valid = RomanianFieldExtractor.isValidCNP(cnp)
            return Parsed(value: .text(cnp), passed: valid, tier: valid ? .deterministic : .heuristic)
        case .documentNumber(let pattern):
            guard let match = TextPattern.first(pattern, in: value.uppercased()) else { return nil }
            let joined = match.groups.dropFirst().compactMap { $0 }.joined().uppercased()
            return joined.contains(where: \.isNumber) ? Parsed(value: .text(joined), passed: true) : nil
        case .date, .dateRange:
            return RomanianFieldExtractor.dates(inLine: RomanianText.fold(value), index: 0, window: window).first.map { Parsed(value: .day($0.day), passed: true) }
        case .sex:
            let letters = value.uppercased().filter(\.isLetter)
            guard let letter = letters.first(where: { $0 == "M" || $0 == "F" }) else { return nil }
            return Parsed(value: .text(String(letter)), passed: letters.count <= 3)
        case .country:
            if let code = TextPattern.first(#"\b([A-Z]{3})\b"#, in: value, caseInsensitive: false)?[1] {
                return Parsed(value: .text(code), passed: true)
            }
            guard value.count <= 30, value.contains(where: \.isLetter) else { return nil }
            return Parsed(value: .text(value), passed: value.allSatisfy { $0.isLetter || $0 == " " })
        case .text:
            return value.contains(where: \.isLetter) ? Parsed(value: .text(value), passed: true) : nil
        case .categories:
            // "[A] [B] [C]", "A B C" or "A,B,C" → "A, B, C"; only real EU categories count.
            let tokens = value.uppercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
            guard !tokens.isEmpty, tokens.allSatisfy(drivingCategories.contains) else { return nil }
            return Parsed(value: .text(tokens.joined(separator: ", ")), passed: true)
        case .cardLastFour:
            // Only the last four digits ever leave this line; the number itself is never a value.
            return PaymentCardNumbers.lastFour(in: value, strict: true).map { Parsed(value: .text($0), passed: true) }
        case .cardExpiry:
            return cardExpiry(in: value, window: window).map { Parsed(value: .day($0), passed: true) }
        case .cardNetwork:
            if let network = PaymentCardNetwork.read(in: RomanianText.fold(value)) { return Parsed(value: .text(network), passed: true) }
            let digits = PaymentCardNumbers.runs(in: value, strict: true).first?.digits
            return digits.flatMap(PaymentCardNumbers.network(ofNumber:)).map { Parsed(value: .text($0), passed: false) }
        case .bankName:
            return RomanianBanks.name(in: RomanianText.fold(value)).map { Parsed(value: .text($0), passed: true) }
        case .recordResult:
            let folded = RomanianText.fold(value)
            guard folded.contains("figureaza"), value.count <= 160 else { return nil }
            return Parsed(value: .text(value.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".:;")))), passed: true)
        }
    }

    /// A card's expiry printed as month and year ("08/28", "08/2028"): the last day of
    /// that month, the two-digit year read in the expiry's window. The latest one when a
    /// card prints two (a "member since" month is earlier).
    static func cardExpiry(in value: String, window: DateWindow) -> CaptureDay? {
        let pattern = #"(?<![\d/])(0[1-9]|1[0-2])\s?[/\-.]\s?(\d{4}|\d{2})(?![\d/])"#
        let days = TextPattern.matches(pattern, in: value).compactMap { match -> CaptureDay? in
            guard let month = match[1].flatMap(Int.init), let yearText = match[2], let year = Int(yearText) else { return nil }
            let first = yearText.count == 2 ? window.resolve(twoDigitYear: year, month: month, day: 1) : CaptureDay(year: year, month: month, day: 1)
            guard let first else { return nil }
            return (28...31).reversed().lazy.compactMap { CaptureDay(year: first.year, month: first.month, day: $0) }.first
        }
        return days.filter(window.contains).max() ?? days.max()
    }

    /// A validity range at its label: two dates, the first before the second, on the
    /// value or on the line after the label. Each date's two-digit year is read in its
    /// own window ("12.03.18-31.12.28": issued 2018, valid until 2028).
    private static func dateRange(at found: LabelledLayout<IdentityLabelKey>.Found?, start: DateWindow, end: DateWindow) -> (start: CaptureDay, end: CaptureDay, source: String)? {
        guard let found else { return nil }
        let starts = RomanianFieldExtractor.dates(inLine: found.folded, index: found.label.line, window: start)
        let ends = RomanianFieldExtractor.dates(inLine: found.folded, index: found.label.line, window: end)
        guard starts.count == 2, ends.count == 2, starts[0].day < ends[1].day else { return nil }
        return (starts[0].day, ends[1].day, found.source)
    }

    /// A value in the field's usual region that passes its format.
    private static func inRegion(_ region: TextBox, of text: CaptureText, format: IdentityFormat, window: DateWindow) -> (value: CaptureValue, source: String)? {
        for (index, box) in text.boxes.enumerated() {
            guard let box, box.midX >= region.minX, box.midX <= region.maxX, box.midY >= region.minY, box.midY <= region.maxY,
                  let parsed = parse(text.original[index], as: format, window: window), parsed.passed else { continue }
            return (parsed.value, text.original[index])
        }
        return nil
    }

    /// A line anywhere that is exactly a value of this format (a CNP: anywhere on a line,
    /// but only with a valid control digit).
    private static func anywhere(in text: CaptureText, format: IdentityFormat, window: DateWindow) -> (value: CaptureValue, source: String?, confidence: Double, tier: CaptureTier)? {
        switch format {
        case .personalNumber:
            return RomanianFieldExtractor.personalNumber(in: text).map { (.text($0.0), $0.1, 0.97, .deterministic) }
        case .cardNetwork:
            // The network's printed name wins over what the number's first digits suggest.
            if let network = PaymentCardNetwork.read(in: text.joinedFolded) { return (.text(network), nil, anywhere, .heuristic) }
            let digits = text.joiningRows().original.lazy.compactMap { PaymentCardNumbers.runs(in: $0, strict: true).first?.digits }.first
            return digits.flatMap(PaymentCardNumbers.network(ofNumber:)).map { (.text($0), nil, failedFormat, .heuristic) }
        case .cardLastFour, .bankName, .recordResult:
            // Fragments on one row read together, so a number printed in groups is one number.
            // A card's line is never kept as the source: it would carry the card's number.
            let rows = text.joiningRows()
            for line in rows.original + [rows.original.joined(separator: " ")] {
                guard let parsed = parse(line, as: format) else { continue }
                return (parsed.value, format == .recordResult ? line : nil, parsed.passed ? anywhere : failedFormat, .heuristic)
            }
            return nil
        case .cardExpiry:
            let days = text.joiningRows().original.compactMap { cardExpiry(in: $0, window: window) }
            return (days.filter(window.contains).max() ?? days.max()).map { (.day($0), nil, anywhere, .heuristic) }
        default:
            break
        }
        guard case .documentNumber(let pattern) = format else { return nil }
        let whole = "^" + pattern.replacingOccurrences(of: #"\b"#, with: "") + "$"
        for line in text.original {
            if let parsed = parse(line, as: .documentNumber(pattern: whole)) { return (parsed.value, line, anywhere, .heuristic) }
        }
        return nil
    }

    // MARK: - Cross-checks

    /// A valid CNP encodes the birth date and sex: they are added when missing, made
    /// certain when the printed ones agree, and replaced when they don't.
    private static func crossCheckPersonalNumber(_ fields: inout [CaptureField]) {
        guard let cnp = fields.first(where: { $0.key == .personalNumber }), cnp.tier == .deterministic,
              let digits = cnp.value.text else { return }
        let derived: [(CaptureFieldKey, CaptureValue?)] = [
            (.birthDate, RomanianFieldExtractor.birthDate(fromCNP: digits).map(CaptureValue.day)),
            (.sex, RomanianFieldExtractor.sex(fromCNP: digits).map(CaptureValue.text)),
        ]
        for (key, value) in derived {
            guard let value else { continue }
            let checked = CaptureField(key: key, value: value, confidence: 0.97, sourceText: cnp.sourceText, tier: .deterministic)
            if let index = fields.firstIndex(where: { $0.key == key }) {
                if fields[index].value == value {
                    fields[index] = CaptureField(key: key, value: value, confidence: 0.97, sourceText: fields[index].sourceText, tier: .deterministic)
                } else {
                    fields[index] = checked
                }
            } else {
                fields.append(checked)
            }
        }
    }
}

extension RomanianFieldExtractor {

    // MARK: - CNP

    /// A Romanian personal numeric code with a valid control digit (key 279146358279).
    public static func isValidCNP(_ digits: String) -> Bool {
        let numbers = digits.compactMap(\.wholeNumberValue)
        guard numbers.count == 13, digits.count == 13, (1...9).contains(numbers[0]) else { return false }
        let key = [2, 7, 9, 1, 4, 6, 3, 5, 8, 2, 7, 9]
        let sum = zip(numbers.prefix(12), key).reduce(0) { $0 + $1.0 * $1.1 }
        let control = sum % 11 == 10 ? 1 : sum % 11
        return control == numbers[12]
    }

    /// The first valid CNP in the text, with the line it was on.
    static func personalNumber(in text: CaptureText) -> (String, String)? {
        for (index, line) in text.original.enumerated() {
            let compact = line.filter { !$0.isWhitespace }
            for match in TextPattern.matches(#"(?<!\d)(\d{13})(?!\d)"#, in: compact) {
                if let digits = match[1], isValidCNP(digits) { return (digits, text.original[index]) }
            }
        }
        return nil
    }

    /// The birth date a CNP encodes: sex and century digit, then YYMMDD.
    static func birthDate(fromCNP cnp: String) -> CaptureDay? {
        let numbers = cnp.compactMap(\.wholeNumberValue)
        guard numbers.count == 13 else { return nil }
        let century: Int
        switch numbers[0] {
        case 1, 2: century = 1900
        case 3, 4: century = 1800
        case 5, 6: century = 2000
        default: return nil // 7–9: residents, century not encoded
        }
        let year = century + numbers[1] * 10 + numbers[2]
        let month = numbers[3] * 10 + numbers[4]
        let day = numbers[5] * 10 + numbers[6]
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        return CaptureDay(year: year, month: month, day: day)
    }

    /// The sex a CNP encodes: odd first digits are men, even ones women (9: foreigners, not encoded).
    static func sex(fromCNP cnp: String) -> String? {
        guard let first = cnp.first?.wholeNumberValue, (1...8).contains(first) else { return nil }
        return first.isMultiple(of: 2) ? "F" : "M"
    }

    /// A printed name in capitals, kept only if it looks like a name.
    static func personName(_ raw: String) -> String? {
        let letters = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "<.,:")))
        guard letters.count >= 2, letters.count <= 60,
              letters.allSatisfy({ $0.isLetter || $0 == " " || $0 == "-" || $0 == "'" }) else { return nil }
        return letters
    }
}
