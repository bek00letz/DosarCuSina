import Foundation

extension CaptureResult {
    /// The same result with every card number masked (`PaymentCardNumbers`): in the text
    /// read and shown, in what is kept to read the page again, in every reader's values and
    /// their sources, the AI provider's included. Strict for a bank card, so a misread digit
    /// can't let its number through; only `cardLastFour` keeps four digits, and nothing
    /// more. A value read for a field whose type tells it apart from a card (a microchip that
    /// passes its check) stays whole in its field and, the same digits, in the text read
    /// (`keptWhole`), so the document's kept text holds it as its section will.
    /// `CaptureEngine` hands out no other kind of result.
    func withoutCardNumbers() -> CaptureResult {
        let strict = kind == .bankCard
        let kept = strict ? PaymentCardNumbers.KeptWhole.nothing : keptWhole
        func text(_ value: String) -> String { PaymentCardNumbers.redact(value, strict: strict, keeping: kept) }
        return CaptureResult(
            id: id,
            kind: kind,
            kindConfidence: kindConfidence,
            fields: fields.map { $0.withoutCardNumbers(strict: strict, keeping: kept) },
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
                    modelFields: source.modelFields.map { $0.withoutCardNumbers(strict: strict, keeping: kept) },
                    aiFields: source.aiFields.map { $0.map { $0.withoutCardNumbers(strict: strict, keeping: kept) } },
                    isSinglePhoto: source.isSinglePhoto
                )
            }
        )
    }

    /// The values its readers read for a field whose type tells them apart from a card number
    /// (`CaptureFieldKey.typeKeptWhole`), by every reader, as `PaymentCardNumbers.KeptWhole`
    /// keeps them: only those that pass that type's check.
    var keptWhole: PaymentCardNumbers.KeptWhole {
        let readers = fields + (source?.modelFields ?? []) + (source?.aiFields ?? [])
        let read = readers.map { ($0.key, $0.value) } + fieldAlternatives.map { ($0.key, $0.alternative.value) }
        return PaymentCardNumbers.KeptWhole(typed: read.compactMap { key, value in
            guard let type = key.typeKeptWhole, let text = value.text else { return nil }
            return (text: text, type: type)
        })
    }
}

extension CaptureField {
    /// The field with any card number in its value or its source masked; what the result keeps
    /// whole (`kept`) stays in its source line.
    func withoutCardNumbers(strict: Bool, keeping kept: PaymentCardNumbers.KeptWhole = .nothing) -> CaptureField {
        CaptureField(key: key, value: value.withoutCardNumbers(key: key, strict: strict), confidence: confidence,
                     sourceText: sourceText.map { PaymentCardNumbers.redact($0, strict: strict, keeping: kept) }, tier: tier)
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
