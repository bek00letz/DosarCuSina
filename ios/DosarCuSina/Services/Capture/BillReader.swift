import Foundation

extension CaptureFieldKey {
    /// The index a bill prints as the meter's previous reading ("Index vechi"). A label of
    /// the bill's table, read only to check the new index against; never a field of its own.
    static let previousMeterIndex: CaptureFieldKey = "previousMeterIndex"
}

/// Reads what a bill says about itself, for every provider the same way: when it was
/// issued, when to pay it, the meter's index and how to pay it.
///
/// The labels are the bill kind's own table (`CaptureKindProfile.billLabels`), read with
/// `LabelledLayout`, so a new wording is a new row. Numbers go through `RomanianNumber`,
/// told what they are, and dates through the one date reader (`RomanianFieldExtractor.dates`),
/// so a meter index that could read two ways ("12.345") is marked "Verifică" like every
/// other value. Pure: text in, fields out; which value wins is `ReadingArbiter`'s.
///
/// What ties the bill to its contract (client code, POD, CLC, contract number, the service,
/// the supply address, direct debit) is `ContractReader`'s; the total and the invoice
/// number are read as on any invoice.
enum BillReader {

    /// How far after its issue a bill is usually due, for a due date the bill doesn't label.
    static let usualPaymentMonths = 2
    /// The shortest code read after a payment label, so a stray "nr. 12" is never one.
    static let shortestPaymentCode = 6

    /// The fields a bill prints under its own labels. `window` decides the century of
    /// two-digit years.
    static func fields(in text: CaptureText, window: DateWindow = .aroundToday) -> [CaptureField] {
        let layout = Self.layout(of: text)
        var fields: [CaptureField] = []

        let issued = layout.day(for: .issueDate, window: window)
        if let (day, source) = issued {
            fields.append(field(.issueDate, .day(day), 0.7, source))
        }
        if let due = dueDate(in: text, layout: layout, issued: issued?.0, window: window) {
            fields.append(due)
        }
        if let index = meterIndex(in: layout) {
            fields.append(index)
            if let reading = readingBasis(in: text, layout: layout) { fields.append(reading) }
        }
        if let code = paymentCode(in: text, layout: layout) {
            fields.append(code)
        }
        return fields
    }

    /// The bill's own labels on a page: its kind's table (`CaptureKindProfile.billLabels`).
    static func layout(of text: CaptureText) -> LabelledLayout<CaptureFieldKey> {
        LabelledLayout(text: text, words: CaptureDocumentKind.utilityInvoice.profile.labels)
    }

    // MARK: - Dates

    /// The day to pay by: its label's date; else, when the bill doesn't label it, the latest
    /// date in the usual time after its issue, marked "Verifică" (a guess, never a reading).
    private static func dueDate(in text: CaptureText, layout: LabelledLayout<CaptureFieldKey>, issued: CalendarDay?,
                                window: DateWindow) -> CaptureField? {
        if let (day, source) = layout.day(for: .dueDate, window: window) {
            return field(.dueDate, .day(day), 0.75, source)
        }
        guard let issued, let latest = issued.printed(addingMonths: usualPaymentMonths) else { return nil }
        let candidates = RomanianFieldExtractor.allDates(in: text, window: window).filter { $0.day > issued && $0.day <= latest }
        guard let guess = candidates.max(by: { $0.day < $1.day }) else { return nil }
        return field(.dueDate, .day(guess.day), CaptureField.checkThreshold - 0.15, text.original[guess.line])
    }

    // MARK: - The meter's index

    /// The new index, read as a meter index. Marked "Verifică" when it could read two ways,
    /// when the bill prints two different new indexes (two registers, day and night), or
    /// when it is lower than the previous one the bill prints.
    static func meterIndex(in layout: LabelledLayout<CaptureFieldKey>) -> CaptureField? {
        let readings = layout.allFound(for: .meterIndex).compactMap { found in meterNumber(in: found.folded).map { ($0, found.source) } }
        guard let (reading, source) = readings.first else { return nil }
        let twoValues = readings.contains { $0.0.value != reading.value }
        let lower = previousIndex(in: layout).map { reading.value < $0.value } ?? false
        let confidence = CaptureAnalyzer.confidence(0.75, ambiguous: reading.needsCheck || twoValues || lower)
        return field(.meterIndex, .number(reading.value), confidence, source)
    }

    /// The previous index the bill prints ("Index vechi"), read as a meter index.
    static func previousIndex(in layout: LabelledLayout<CaptureFieldKey>) -> RomanianNumber.Reading? {
        layout.allFound(for: .previousMeterIndex).lazy.compactMap { meterNumber(in: $0.folded) }.first
    }

    /// The first number in a label's value that isn't part of a date, read by the one number
    /// reader as a meter index. Nil when that number can't be read one way only.
    static func meterNumber(in folded: String) -> RomanianNumber.Reading? {
        meterNumberAndRest(in: folded)?.reading
    }

    /// The index's number in a label's value (`meterNumber`) and what is printed after it.
    private static func meterNumberAndRest(in folded: String) -> (reading: RomanianNumber.Reading, rest: Substring)? {
        let dates = RomanianFieldExtractor.dates(inLine: folded, index: 0).map(\.range)
        let numbers = TextPattern.matches(#"(?<![\d.,])(\d+(?:[.,]\d+)*)(?!\d)"#, in: folded)
        guard let first = numbers.first(where: { number in !dates.contains { $0.overlaps(number.range) } }),
              let raw = first[1], let reading = try? RomanianNumber.read(raw, as: .meterIndex, from: .document).get() else { return nil }
        return (reading, folded[first.range.upperBound...])
    }

    // MARK: - How the index was taken

    /// How the bill says its new index was taken (`.meterReading`, a `ReadingBasis` key), by
    /// its kind's cues (`CaptureKindProfile.meterReadingCues`), the strongest place first: the
    /// index's own label and what is printed beside its number ("Index estimat: 12.345",
    /// "12.345 (E)"); else a row that says how it was read ("Tip citire: citire reală"); else a
    /// regularisation bill, whose index is read. Nil when the bill doesn't say, or says both.
    static func readingBasis(in text: CaptureText, layout: LabelledLayout<CaptureFieldKey>) -> CaptureField? {
        guard let cues = CaptureDocumentKind.utilityInvoice.profile.meterReadingCues else { return nil }
        for found in layout.allFound(for: .meterIndex) {
            guard let (_, rest) = meterNumberAndRest(in: found.folded) else { continue }
            let label = String(text.folded[found.label.line][found.label.start..<found.label.end])
            if let basis = cues.basis(saidBy: label + " " + rest, marksAtStart: rest) {
                return field(.meterReading, .text(basis.rawValue), 0.75, found.source)
            }
            break
        }
        for found in layout.allFound(for: .meterReading) {
            if let basis = cues.basis(saidBy: found.folded, marksAtStart: Substring(found.folded)) {
                return field(.meterReading, .text(basis.rawValue), 0.7, found.source)
            }
        }
        if let line = cues.regularisationLine(in: text) {
            return field(.meterReading, .text(ReadingBasis.read.rawValue), 0.7, text.original[line])
        }
        return nil
    }

    // MARK: - How to pay

    /// The code to pay the bill with: after its label, else the digits printed under the
    /// barcode. A decoded barcode, when there is one, is read deterministically and wins
    /// (`CaptureAnalyzer`); a code read off the text proves nothing by itself.
    private static func paymentCode(in text: CaptureText, layout: LabelledLayout<CaptureFieldKey>) -> CaptureField? {
        for found in layout.allFound(for: .paymentCode) {
            if let code = ContractReader.code(in: found.value), code.count >= shortestPaymentCode {
                return field(.paymentCode, .text(code), 0.7, found.source)
            }
        }
        // The digits printed under the barcode: a run as long as a payment barcode's.
        let length = CaptureBarcode.paymentCodeDigits
        let run = #"(?<![\d.,])(\d{"# + "\(length.lowerBound),\(length.upperBound)" + #"})(?![\d.,])"#
        for line in text.original {
            if let match = TextPattern.first(run, in: line), let digits = match[1] {
                return field(.paymentCode, .text(digits), 0.6, line)
            }
        }
        return nil
    }

    private static func field(_ key: CaptureFieldKey, _ value: CaptureValue, _ confidence: Double, _ source: String?) -> CaptureField {
        CaptureField(key: key, value: value, confidence: confidence, sourceText: source, tier: .heuristic)
    }
}

/// How a bill says its meter's index was taken, as data on the bill kind's profile
/// (`CaptureKindProfile.meterReadingCues`, a utility bill's `billReadingCues`), read the one
/// way by `BillReader.readingBasis`. A new wording is a new word in the table.
struct MeterReadingCues: Sendable {
    /// Words, folded, that say the index was estimated.
    let estimatedWords: [String]
    /// Words, folded, that say it was read: by the distributor, by the customer, or on a
    /// regularisation.
    let readWords: [String]
    /// What a bill prints as a mark of an estimated index: right after its number ("12.345 E"),
    /// or as the whole value of a reading-type row.
    let estimatedMarks: [String]
    /// The marks of a read index ("R", "C" for citit, "A" for autocitit).
    let readMarks: [String]
    /// Words, folded, anywhere on the page that make the bill a regularisation.
    let regularisationWords: [String]
    /// A line that is only one of these, folded, is a regularisation's heading.
    let regularisationHeadings: [String]

    /// What `folded` says about the index: estimated, read, or nothing (nil) when it says
    /// neither or both (a legend, "E = estimat, R = real"). `marksAtStart` is where a mark may
    /// stand on its own, at its start, in brackets or not.
    func basis(saidBy folded: String, marksAtStart: Substring) -> ReadingBasis? {
        let estimated = estimatedWords.contains { CaptureText.containsWord($0, inFolded: folded) } || Self.startsWith(estimatedMarks, marksAtStart)
        let read = readWords.contains { CaptureText.containsWord($0, inFolded: folded) } || Self.startsWith(readMarks, marksAtStart)
        switch (estimated, read) {
        case (true, false): return .estimated
        case (false, true): return .read
        default: return nil
        }
    }

    /// Whether `text` says, anywhere, what `basis` is said with (its words; a regularisation for
    /// read): how a model's answer about the index is checked against the phone's text. A mark
    /// alone ("E") proves nothing there.
    func mentions(_ basis: ReadingBasis, in text: CaptureText) -> Bool {
        switch basis {
        case .estimated: estimatedWords.contains { text.containsWord($0) }
        case .read: readWords.contains { text.containsWord($0) } || regularisationLine(in: text) != nil
        }
    }

    /// The first line that makes the bill a regularisation, if any.
    func regularisationLine(in text: CaptureText) -> Int? {
        text.folded.indices.first { index in
            let line = text.folded[index]
            let bare = line.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            return regularisationHeadings.contains(bare) || regularisationWords.contains { CaptureText.containsWord($0, inFolded: line) }
        }
    }

    /// Whether `text` starts with one of `marks` standing on its own: "e", "(e)", "- r".
    private static func startsWith(_ marks: [String], _ text: Substring) -> Bool {
        let alternatives = marks.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        return TextPattern.first(#"^[\s\-–:]*[(\[]?\s*(?:"# + alternatives + #")\s*[)\]]?(?![\p{L}\d])"#, in: String(text)) != nil
    }
}
