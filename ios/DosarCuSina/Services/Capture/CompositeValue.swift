import Foundation

/// A value printed in pieces: a series and a number, kept as one value.
///
/// Romanian documents print identifiers in parts, in several ways: "Seria și numărul:
/// RO/00/X00/XX 123456789" on one line; "Seria RO/00/X00/XX" over "Nr. 123456789"; side by
/// side in columns; "SERIA XT NR 123456" inline; under one header ("Codul țării / Codul
/// asigurătorului / Numărul") with the series on one line and the number on the next. What
/// a value looks like is declared once here, as data; where it is printed is the label
/// table's (`LabelledLayout.composite(_:for:)` reads it), so a new document is a new shape
/// or a new label, never new reading code.
///
/// The rules every reader shares:
/// - a value is the series and the number joined (`joined`), written one way whoever read it;
/// - a label word ("nr", "seria", "număr") is never a series or a number;
/// - a number is never another field's: it follows its own label or its series, never a
///   stray "Nr." ("Nr. înmatriculare", "Nr. contract") elsewhere on the page;
/// - a part read alone never beats the whole value, and the two parts read in two places
///   are joined into it (`ReadingArbiter`, `CompositeValue.reconcile`).
struct CompositeValue: Sendable, Hashable {
    /// How the series is written, as a regular expression over folded, uppercased text
    /// with no capture groups. Nil when the value is printed as one code (a contract's).
    let series: String?
    /// How the number is written, likewise. It always holds a digit.
    let number: String
    /// What goes between the parts when they are joined: "" for "XT123456" (as the
    /// machine-readable zone writes it), " " for "RO/00/X00/XX 123456789".
    let joiner: String
    /// The value isn't whole without its series (an identity card's "XT").
    let requiresSeries: Bool
    /// A placeholder of the whole value, for the AI provider's question.
    let example: String

    /// A number's own label inside a value: "nr.", "Nr.:", "număr", "No.".
    private static let connector = #"(?:(?:NR|NO|NUMARUL|NUMAR|NUMBER)\s*\.?\s*:?\s*)"#
    private static let notAPartWord = "(?!(?:" + CompositeLabels.partWords.joined(separator: "|") + ")(?![A-Z0-9]))"
    /// What separates a series from its number: the number's label, a comma, a space, or
    /// nothing when a letter meets a digit ("XT123456"). Never nothing between two digits,
    /// so a series ending in digits never takes the number's first ones.
    private static let separator = #"(?:\s*[,;]?\s*"# + connector + #"|\s*[,;]\s*|\s+|(?<=[A-Z])(?=\d))"#

    // MARK: - Shapes

    /// An insurance policy (RCA, CASCO, a home's): "RO/00/X00/XX" then up to ten digits.
    /// Some policies print only a number.
    static let policy = CompositeValue(
        series: #"[A-Z]{1,4}(?:/[A-Z0-9]{1,6}){0,4}"#, number: #"\d{5,12}"#, joiner: " ", requiresSeries: false,
        example: "RO/00/X00/XX 123456789"
    )
    /// An identity card: two letters and six or seven digits, written together.
    static let identityCard = CompositeValue(
        series: #"[A-Z]{2}"#, number: #"\d{6,7}"#, joiner: "", requiresSeries: true, example: "XT123456"
    )
    /// An invoice: "seria EXM nr. 0012345", or one code ("XYZ-2026-0001").
    static let invoice = CompositeValue(
        series: #"[A-Z]{1,8}"#, number: #"(?=[A-Z0-9-]*\d)[A-Z0-9][A-Z0-9-]{0,23}[A-Z0-9]"#, joiner: " ", requiresSeries: false,
        example: "EXM 0012345"
    )
    /// A contract: one code ("12345/2026", "EX-000123"). Kept as one code so it still
    /// matches the codes subscriptions already keep.
    static let contract = CompositeValue(
        series: nil, number: #"(?=[A-Z0-9/.-]*\d)[A-Z0-9][A-Z0-9/.-]{1,28}[A-Z0-9]"#, joiner: " ", requiresSeries: false,
        example: "12345/2026"
    )
    /// A vehicle's identity card (CIV): a letter or two and six or seven digits, written together.
    static let vehicleCard = CompositeValue(
        series: #"[A-Z]{1,2}"#, number: #"\d{6,7}"#, joiner: "", requiresSeries: true, example: "J123456"
    )

    /// The shape of the fields that are always printed in parts, whatever the document.
    /// A document number's shape depends on the document: its template says
    /// (`IdentityFormat.composite`), through `shape(of:kind:)`.
    static let byKey: [CaptureFieldKey: CompositeValue] = [
        .policyNumber: .policy,
        .invoiceNumber: .invoice,
        .contractNumber: .contract,
        .civNumber: .vehicleCard,
    ]

    /// The shape of `key` on a document of `kind`, if it is printed in parts.
    static func shape(of key: CaptureFieldKey, kind: CaptureDocumentKind?) -> CompositeValue? {
        if let shape = byKey[key] { return shape }
        guard let kind else { return nil }
        for template in IdentityTemplates.all where template.kind == kind {
            for field in template.fields where field.key == key {
                if case .composite(let shape) = field.format { return shape }
            }
        }
        return nil
    }

    // MARK: - Reading a value

    /// A value's parts, as read.
    struct Parts: Sendable, Hashable {
        var series: String?
        var number: String?

        var isEmpty: Bool { series == nil && number == nil }
    }

    /// Text prepared for reading parts: folded, uppercased, slashes without spaces
    /// around them ("RO / 00 / X00" is "RO/00/X00").
    static func prepared(_ text: String) -> String {
        let upper = RomanianText.fold(text).uppercased()
        return upper.replacingOccurrences(of: #"\s*/\s*"#, with: "/", options: .regularExpression)
    }

    /// The parts in a printed value: the series and the number together anywhere in it;
    /// else a number alone (its own label may precede it); else, when the value is only a
    /// series, that series, waiting for its number on the next line.
    func parts(in value: String) -> Parts? {
        let text = Self.prepared(value)
        let number = "(" + self.number + ")"
        if let series {
            let both = #"(?<![A-Z0-9/])"# + Self.notAPartWord + "(" + series + ")" + Self.separator + number + #"(?![A-Z0-9])"#
            for match in TextPattern.matches(both, in: text, caseInsensitive: false) {
                if let found = match[1], let digits = match[2], isSeries(found), digits.contains(where: \.isNumber) {
                    return Parts(series: found, number: digits)
                }
            }
        }
        if let alone = numberAlone(in: text, anchored: false) { return Parts(series: nil, number: alone) }
        if let series, let match = TextPattern.first("^[\\s:.,-]*" + Self.notAPartWord + "(" + series + #")[\s:.,;-]*$"#, in: text, caseInsensitive: false),
           let found = match[1], isSeries(found) {
            return Parts(series: found, number: nil)
        }
        return nil
    }

    /// A number printed by itself, perhaps after its own label ("Nr. 123456789"): at the
    /// start of `text` when `anchored`, so the number on the line after a series is never
    /// a field further along ("Nr. înmatriculare B 123 ABC" isn't one).
    func numberAlone(in text: String, anchored: Bool) -> String? {
        let prepared = anchored ? Self.prepared(text) : text
        let start = anchored ? "^[\\s:.,-]*" : #"(?<![A-Z0-9/.-])"#
        let pattern = start + Self.connector + "?(" + number + #")(?![A-Z0-9])"#
        for match in TextPattern.matches(pattern, in: prepared, caseInsensitive: false) {
            if let digits = match[1], digits.contains(where: \.isNumber), !CompositeLabels.partWords.contains(digits) { return digits }
        }
        return nil
    }

    /// A line that is exactly a whole value ("XT123456", "XT 123456"), for a field
    /// searched anywhere on the page when its label wasn't read.
    func wholeLine(_ line: String) -> Parts? {
        let text = Self.prepared(line)
        let number = "(" + self.number + ")"
        let pattern: String
        if let series {
            pattern = #"^\s*"# + Self.notAPartWord + "(" + series + ")" + Self.separator + number + #"\s*$"#
        } else {
            pattern = #"^\s*"# + Self.connector + "?" + number + #"\s*$"#
        }
        guard let match = TextPattern.first(pattern, in: text, caseInsensitive: false) else { return nil }
        let parts = series == nil ? Parts(series: nil, number: match[1]) : Parts(series: match[1], number: match[2])
        guard parts.number?.contains(where: \.isNumber) == true, parts.series.map(isSeries) ?? true else { return nil }
        return parts
    }

    private func isSeries(_ text: String) -> Bool {
        text.contains(where: \.isLetter) && !CompositeLabels.partWords.contains(text)
    }

    /// Whether only a part of a value that has two was read.
    func isPartial(_ parts: Parts) -> Bool {
        series != nil && (parts.series == nil || parts.number == nil)
    }

    /// The value as the binder keeps it: the parts joined.
    func joined(_ parts: Parts) -> String {
        [parts.series, parts.number].compactMap { $0 }.joined(separator: joiner)
    }

    /// The value written the one way, whoever read it ("RO/00/X00/XX NR. 123456789" is
    /// "RO/00/X00/XX 123456789"). Text without the shape is kept as read.
    func normalized(_ value: String) -> String {
        // A value printed as one code is kept as read, so it still matches what is kept.
        guard series != nil, let read = parts(in: value) else { return value }
        return joined(read)
    }

    /// Two readings of the same value, joined: equal, one a part of the other (the whole
    /// wins), or two parts read in two places (joined). Nil when they disagree.
    func agreement(_ first: String, _ second: String) -> String? {
        if RomanianText.compact(first) == RomanianText.compact(second) { return normalized(first) }
        // A value printed as one code has no parts to complete each other.
        guard series != nil, let a = parts(in: first), let b = parts(in: second) else { return nil }
        func compatible(_ x: String?, _ y: String?) -> Bool { x == nil || y == nil || x == y }
        guard compatible(a.series, b.series), compatible(a.number, b.number) else { return nil }
        let merged = Parts(series: a.series ?? b.series, number: a.number ?? b.number)
        return merged.isEmpty ? nil : joined(merged)
    }

    // MARK: - Choosing among readings

    /// How a value was put together, which sets how sure it is.
    enum Quality: Int, Comparable, Sendable {
        /// Two whole values that differ: kept for a look.
        case conflicting
        /// Only a number, where a series is usually printed too.
        case numberOnly
        /// The series and the number, each read at its own label in a different place.
        case joinedFromTwoPlaces
        /// The whole value, read together.
        case whole

        static func < (lhs: Quality, rhs: Quality) -> Bool { lhs.rawValue < rhs.rawValue }

        /// The confidence a value read so gets.
        var confidence: Double {
            switch self {
            case .whole: 0.78
            case .joinedFromTwoPlaces: 0.7
            case .numberOnly: 0.62
            case .conflicting: CaptureConsistency.disputed
            }
        }
    }

    /// A value found on the page.
    struct Found: Sendable {
        let parts: Parts
        let value: String
        let quality: Quality
        let source: String
    }

    /// The value among every place it was printed, top to bottom: the first whole one
    /// (marked when another whole one differs); else a series and a number read apart,
    /// joined; else a number alone, when a value may have no series.
    func choose(_ readings: [(parts: Parts, source: String)]) -> Found? {
        let wholes = readings.filter { $0.parts.number != nil && (series == nil || $0.parts.series != nil) }
        if let first = wholes.first {
            let differs = wholes.contains { RomanianText.compact(joined($0.parts)) != RomanianText.compact(joined(first.parts)) }
            return Found(parts: first.parts, value: joined(first.parts), quality: differs ? .conflicting : .whole, source: first.source)
        }
        let seriesOnly = readings.first { $0.parts.series != nil && $0.parts.number == nil }
        let numberOnly = readings.first { $0.parts.series == nil && $0.parts.number != nil }
        if let seriesOnly, let numberOnly {
            let parts = Parts(series: seriesOnly.parts.series, number: numberOnly.parts.number)
            return Found(parts: parts, value: joined(parts), quality: .joinedFromTwoPlaces, source: seriesOnly.source + " " + numberOnly.source)
        }
        if let numberOnly, !requiresSeries {
            return Found(parts: numberOnly.parts, value: joined(numberOnly.parts), quality: .numberOnly, source: numberOnly.source)
        }
        return nil
    }

    // MARK: - One reader's fields

    /// One reader's fields for a document of `kind`, with its own number written the one
    /// way and a stray "document number" folded into it: a reader that put the policy's
    /// series in one field and its number in another ("Serie și număr" and "Număr poliță")
    /// gets one value. A document carries one number of its own (`CaptureKindProfile.numberKey`).
    static func reconcile(_ fields: [CaptureField], kind: CaptureDocumentKind) -> [CaptureField] {
        var result = fields.map { field -> CaptureField in
            guard let fieldShape = Self.shape(of: field.key, kind: kind), let text = field.value.text else { return field }
            let normalized = fieldShape.normalized(text)
            guard normalized != text else { return field }
            return CaptureField(key: field.key, value: .text(normalized), confidence: field.confidence, sourceText: field.sourceText, tier: field.tier)
        }
        guard let own = kind.profile.numberKey, own != .documentNumber,
              let strayIndex = result.firstIndex(where: { $0.key == .documentNumber }) else { return result }
        let stray = result.remove(at: strayIndex)
        guard let strayText = stray.value.text else { return result }
        let ownShape = Self.shape(of: own, kind: kind)
        if let index = result.firstIndex(where: { $0.key == own }) {
            let existing = result[index]
            guard let ownShape, let text = existing.value.text, let agreed = ownShape.agreement(text, strayText) else { return result }
            result[index] = CaptureField(key: own, value: .text(agreed), confidence: min(existing.confidence, stray.confidence),
                                         sourceText: existing.sourceText ?? stray.sourceText, tier: max(existing.tier, stray.tier))
        } else {
            let value = ownShape?.normalized(strayText) ?? strayText
            result.append(CaptureField(key: own, value: .text(value), confidence: stray.confidence, sourceText: stray.sourceText, tier: stray.tier))
        }
        return result
    }
}

extension CaptureKindProfile {
    /// The field that holds the document's own series and number: a policy's, an
    /// invoice's, a contract's, or an identity document's. Any other number a reader
    /// calls "the document number" on it is folded into this one.
    var numberKey: CaptureFieldKey? {
        [CaptureFieldKey.documentNumber, .policyNumber, .invoiceNumber, .contractNumber].first(where: expectedKeys.contains)
    }
}
