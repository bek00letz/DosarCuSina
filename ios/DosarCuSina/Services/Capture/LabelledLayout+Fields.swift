import Foundation

extension LabelledLayout {
    /// What separates a value from its label, around it.
    static var valueSeparators: CharacterSet { CharacterSet.whitespaces.union(CharacterSet(charactersIn: ":;=|-–—")) }

    /// The value printed at `key`'s labels, read as the field `field` is (`ModelQuestions.format(of:)`,
    /// the one description of a field): each place of the label in turn, and each value it may
    /// have in the order the layout reads them (`allCandidates(for:)`), the first that reads so.
    /// A value printed in parts is read whole (`composite`). The value goes through the shared
    /// readers: a day through the one date reader, an amount through `RomanianFieldExtractor.amounts`,
    /// a number through `RomanianNumber`, text as printed. Nil for a field whose value is a
    /// judgement about the page (a service, a cover, a reading's basis) rather than text after a label.
    func field(_ key: Key, as field: CaptureFieldKey, kind: CaptureDocumentKind, window: DateWindow, currency: String,
               confidence: Double) -> CaptureField? {
        if let shape = CompositeValue.shape(of: field, kind: kind) {
            guard let found = composite(shape, for: key) else { return nil }
            return CaptureField(key: field, value: .text(found.value), confidence: min(confidence, found.quality.confidence),
                                sourceText: found.source, tier: .heuristic)
        }
        for found in allCandidates(for: key) {
            guard let (value, ambiguous) = Self.value(of: field, in: found, window: window, currency: currency) else { continue }
            return CaptureField(key: field, value: value, confidence: CaptureAnalyzer.confidence(confidence, ambiguous: ambiguous),
                                sourceText: found.source, tier: .heuristic)
        }
        return nil
    }

    /// A label's value read as `field` is, and whether it could be read two ways ("3,750").
    private static func value(of field: CaptureFieldKey, in found: Found, window: DateWindow, currency: String)
        -> (value: CaptureValue, ambiguous: Bool)? {
        switch ModelQuestions.format(of: field) {
        case .date:
            let line = found.lines.first ?? found.label.line
            return RomanianFieldExtractor.dates(inLine: found.folded, index: line, window: window).first.map { (value: CaptureValue.day($0.day), ambiguous: false) }
        case .money:
            guard let amount = RomanianFieldExtractor.statedAmount(in: RomanianFieldExtractor.amounts(inLine: found.folded)) else { return nil }
            let money = Money(amount.amount, currency: RomanianFieldExtractor.currency(inLine: found.folded) ?? currency)
            return (.money(money), amount.isAmbiguous)
        case .meterIndex:
            guard let reading = BillReader.meterNumber(in: found.folded) else { return nil }
            return (.number(reading.value), reading.needsCheck)
        case .integer:
            let kilometres = field == .odometer
            guard let number = RomanianFieldExtractor.numbers(inLine: found.folded, as: kilometres ? .kilometres : .count).first else { return nil }
            let value: CaptureValue = kilometres ? .metric(value: number.reading.value, unit: .kilometres) : .number(number.reading.value)
            return (value, number.reading.needsCheck)
        case .text, .documentNumber, .phone, .plate:
            let text = found.value.trimmingCharacters(in: valueSeparators)
            guard RomanianText.compact(text).count >= CaptureLessonLearner.shortestText else { return nil }
            return (.text(text), false)
        default:
            return nil
        }
    }
}
