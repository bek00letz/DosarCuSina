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
    private static func dueDate(in text: CaptureText, layout: LabelledLayout<CaptureFieldKey>, issued: CaptureDay?,
                                window: DateWindow) -> CaptureField? {
        if let (day, source) = layout.day(for: .dueDate, window: window) {
            return field(.dueDate, .day(day), 0.75, source)
        }
        guard let issued, let latest = issued.addingMonths(usualPaymentMonths) else { return nil }
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
        let dates = RomanianFieldExtractor.dates(inLine: folded, index: 0).map(\.range)
        let numbers = TextPattern.matches(#"(?<![\d.,])(\d+(?:[.,]\d+)*)(?!\d)"#, in: folded)
        guard let first = numbers.first(where: { number in !dates.contains { $0.overlaps(number.range) } }),
              let raw = first[1] else { return nil }
        return try? RomanianNumber.read(raw, as: .meterIndex, from: .document).get()
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
