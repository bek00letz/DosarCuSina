import Foundation

extension CaptureResult {
    /// The same result with every card number masked (`PaymentCardNumbers`): in the text
    /// read and shown, in what is kept to read the page again, in every reader's values and
    /// their sources, the AI provider's included. Strict for a bank card, so a misread digit
    /// can't let its number through; only `cardLastFour` keeps four digits, and nothing
    /// more. A value read for a field whose type tells it apart from a card (a microchip that
    /// passes its check) stays whole in its field and, the same digits, in the text read
    /// (`keptWhole`), so the document's kept text holds it as its section will. Whether the
    /// text showed a whole card number before it was masked is kept (`showedCardNumber`), so
    /// `showsCardNumber` still answers for the page. `CaptureEngine` hands out no other kind
    /// of result.
    func withoutCardNumbers() -> CaptureResult {
        let mask = CaptureCardMask(kind: kind, read: readValues)
        let strict = mask.strict
        let kept = mask.kept
        func text(_ value: String) -> String { mask.text(value) }
        let showed = showsCardNumber
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
            },
            showedCardNumber: showed
        )
    }

    /// Whether this page shows a whole card number: its text as read holds one by the
    /// "anywhere" rule (`CaptureCardMask.showsCardNumber`), leaving out the digits a reader read
    /// for a field whose type keeps them whole (a pet's microchip in its microchip field). Once
    /// the text is masked, the fact it showed one before (`showedCardNumber`). The one answer,
    /// by what the page shows and not by its kind, for: its photo is kept only on request
    /// (`photoIsOnRequest`), it is read only on the phone (`PhoneOnlyReading`), the share
    /// inbox shows no picture of it (`InboxPreviewer`), and it may be a personal document
    /// (`IdentitySignals`).
    var showsCardNumber: Bool {
        if showedCardNumber { return true }
        let mask = CaptureCardMask(kind: kind, read: readValues)
        return mask.showsCardNumber(in: recognizedText) || mask.showsCardNumber(in: source?.text ?? "")
    }

    /// Whether saving keeps this page's photo only when the person asks, read as `kind` (the
    /// review's, which the person may have changed): a kind whose photo is kept only on request
    /// (a bank card, `CaptureKindProfile.photoIsOptIn`), or any page that shows a whole card
    /// number (`showsCardNumber`: a receipt, a form or a letter with the number in one piece),
    /// since its photo shows the number the binder never keeps.
    func photoIsOnRequest(as kind: CaptureDocumentKind) -> Bool {
        kind.profile.photoIsOptIn || showsCardNumber
    }

    /// `photoIsOnRequest(as:)` for the kind read.
    var photoIsOnRequest: Bool {
        photoIsOnRequest(as: kind)
    }

    /// The values its readers read for a field whose type tells them apart from a card number
    /// (`CaptureFieldKey.typeKeptWhole`), by every reader, as `PaymentCardNumbers.KeptWhole`
    /// keeps them: only those that pass that type's check.
    var keptWhole: PaymentCardNumbers.KeptWhole {
        CaptureCardMask.keptWhole(readValues)
    }

    /// Every value its readers read, with the field it was read for.
    private var readValues: [(key: CaptureFieldKey, value: CaptureValue)] {
        let readers = fields + (source?.modelFields ?? []) + (source?.aiFields ?? [])
        return readers.map { (key: $0.key, value: $0.value) } + fieldAlternatives.map { (key: $0.key, value: $0.alternative.value) }
    }
}

/// How card numbers are masked in what capture read of one document, the one rule for the
/// result it hands out (`CaptureResult.withoutCardNumbers`) and for the text a language
/// model may read (`SemanticInput.text`), so a model is never shown more of a card than
/// the binder keeps: on a bank card, strictly (`PaymentCardNumbers.redact(_:strict:)`, any
/// long run of digits, nothing kept whole); on anything else, by the "anywhere" rule,
/// keeping whole what a reader read for a field whose type tells it apart from a card
/// (a pet's microchip that passes its check, `CaptureFieldKey.typeKeptWhole`).
struct CaptureCardMask {
    /// Strict: the document is a bank card.
    let strict: Bool
    /// What stays whole; nothing on a bank card.
    let kept: PaymentCardNumbers.KeptWhole

    /// The mask for a document of `kind` whose readers read `values`.
    init(kind: CaptureDocumentKind, read values: [(key: CaptureFieldKey, value: CaptureValue)]) {
        strict = kind == .bankCard
        kept = strict ? .nothing : Self.keptWhole(values)
    }

    /// The text with its card numbers masked.
    func text(_ value: String) -> String {
        PaymentCardNumbers.redact(value, strict: strict, keeping: kept)
    }

    /// Whether `text` shows a whole card number: one the "anywhere" rule finds
    /// (`PaymentCardNumbers.containsCardNumber`), leaving out what this mask keeps whole. The one
    /// rule for "the page shows a whole card number", on the text as read (the engine, before
    /// anything is sent) and on a result (`CaptureResult.showsCardNumber`). On a bank card
    /// nothing is kept whole, so any card-shaped number counts.
    func showsCardNumber(in text: String) -> Bool {
        PaymentCardNumbers.containsCardNumber(text, keeping: kept)
    }

    /// What of `values` stays whole: those read for a field whose type keeps them whole, as
    /// `PaymentCardNumbers.KeptWhole` keeps them (only those that pass that type's check).
    static func keptWhole(_ values: [(key: CaptureFieldKey, value: CaptureValue)]) -> PaymentCardNumbers.KeptWhole {
        PaymentCardNumbers.KeptWhole(typed: values.compactMap { key, value in
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
