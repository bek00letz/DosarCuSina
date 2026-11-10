import Foundation

extension CaptureResult {
    /// The same result with every card number masked (`PaymentCardNumbers`): in the text
    /// read and shown, in what is kept to read the page again, in every reader's values and
    /// their sources, the AI provider's included. Strict for a bank card, so a misread digit
    /// can't let its number through; only `cardLastFour` keeps four digits, and nothing
    /// more. `CaptureEngine` hands out no other kind of result.
    func withoutCardNumbers() -> CaptureResult {
        let strict = kind == .bankCard
        func text(_ value: String) -> String { PaymentCardNumbers.redact(value, strict: strict) }
        return CaptureResult(
            id: id,
            kind: kind,
            kindConfidence: kindConfidence,
            fields: fields.map { $0.withoutCardNumbers(strict: strict) },
            suggestions: suggestions,
            reminder: reminder,
            recognizedText: text(recognizedText),
            barcodes: barcodes,
            document: document,
            notices: notices,
            kindEvidence: kindEvidence,
            kindAlternatives: kindAlternatives,
            fieldAlternatives: fieldAlternatives.map { alternative in
                CaptureFieldAlternative(key: alternative.key, alternative: CaptureAlternative(
                    alternative.alternative.value.withoutCardNumbers(key: alternative.key, strict: strict), source: alternative.alternative.source))
            },
            readWithCloudModel: readWithCloudModel,
            source: source.map { source in
                CaptureReadingSource(
                    text: text(source.text),
                    pages: source.pages.map { page in page.map { RecognizedLine(text($0.text), box: $0.box) } },
                    barcodes: source.barcodes,
                    referenceDate: source.referenceDate,
                    modelFields: source.modelFields.map { $0.withoutCardNumbers(strict: strict) },
                    aiFields: source.aiFields.map { $0.map { $0.withoutCardNumbers(strict: strict) } },
                    isSinglePhoto: source.isSinglePhoto
                )
            }
        )
    }
}

extension CaptureField {
    /// The field with any card number in its value or its source masked.
    func withoutCardNumbers(strict: Bool) -> CaptureField {
        CaptureField(key: key, value: value.withoutCardNumbers(key: key, strict: strict), confidence: confidence,
                     sourceText: sourceText.map { PaymentCardNumbers.redact($0, strict: strict) }, tier: tier)
    }
}

extension CaptureFieldKey {
    /// The field type a value read for this key is, when that type's own check tells it apart
    /// from a card number (`PaymentCardNumbers.keepsWhole`): a pet's microchip.
    var typeKeptWhole: FieldType? {
        self == .microchip ? .microchip : nil
    }
}

extension CaptureValue {
    /// The value with any card number masked; a card's last four digits stay four digits, and a
    /// value its own type tells apart from a card (a microchip that passes its check) stays whole.
    func withoutCardNumbers(key: CaptureFieldKey, strict: Bool) -> CaptureValue {
        switch self {
        case .text(let text):
            if key == .cardLastFour { return PaymentCardNumbers.lastFour(of: text).map(CaptureValue.text) ?? self }
            if !strict, PaymentCardNumbers.keepsWhole(text, as: key.typeKeptWhole) { return self }
            return .text(PaymentCardNumbers.redact(text, strict: strict))
        case .lineItems(let items):
            return .lineItems(items.map { item in
                CaptureLineItem(description: PaymentCardNumbers.redact(item.description, strict: strict), quantity: item.quantity,
                                amount: item.amount, componentKey: item.componentKey, isLabour: item.isLabour)
            })
        default:
            return self
        }
    }
}
