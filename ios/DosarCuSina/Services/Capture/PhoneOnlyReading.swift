import Foundation

/// Documents read only on the phone, never by the person's AI provider: not on "Citește
/// mai bine", not by "Citește automat", not when pages are added and read again. Which
/// documents is data on their type (`DocumentType.readOnPhoneOnly`: a bank card); this is
/// the one rule for whether a capture may be one, and so whether it may go to the provider.
///
/// When the phone can't be sure a page isn't one, it is treated as one: the kind read, or
/// any kind another reader saw, is one; the page shows a card number (whole, or already
/// masked as "•••• 4821"); it carries the words printed only on such a document ("VALID
/// THRU"); or the person is adding one (the capture starts from its page).
///
/// Applied where reading by the provider is decided: the engine, before anything is sent
/// (`CaptureEngine`, so a reading again with added pages is checked on what the phone read
/// of them); "Citește automat" (`AIProviderSettings.automaticReading`); the review's button
/// (`CaptureReview.providerMayRead`); and the capture's reading again (`CaptureSession`).
enum PhoneOnlyReading {
    /// A kind of document that is read only on the phone.
    static func isPhoneOnly(_ kind: CaptureDocumentKind) -> Bool {
        DocumentType.isReadOnPhoneOnly(kind.profile.documentType)
    }

    /// A section holds such a document: a bank card's own page, where "Adaugă poza actului" starts.
    static func holdsOne(_ values: FieldValues) -> Bool {
        DocumentType.isReadOnPhoneOnly(values[DocumentType.typeFieldKey]?.textValue)
    }

    /// What the phone read may be such a document: any of `kinds` is one, or `text` shows
    /// a card number or the words printed only on one.
    static func mayBeOne(kinds: [CaptureDocumentKind], text: String) -> Bool {
        kinds.contains(where: isPhoneOnly) || IdentitySignals.hasCardNumber(text) || hasDecisiveWords(text)
    }

    /// A reading that may be such a document: its kind, a kind another reader saw, its text
    /// (masked or not), or the engine already kept it on the phone (`readOnPhoneOnly`).
    static func mayBeOne(_ result: CaptureResult) -> Bool {
        if result.notices.contains(.readOnPhoneOnly) { return true }
        let kinds = [result.kind] + result.kindAlternatives.map(\.value)
        return mayBeOne(kinds: kinds, text: result.recognizedText) || mayBeOne(kinds: [], text: result.source?.text ?? "")
    }

    /// The words that weigh most for such a document's templates (`IdentityTemplates`):
    /// "valid thru", "good thru". Printed only on a payment card, so a page that carries
    /// them is one even when its number didn't read.
    static let decisiveWords: [String] = IdentityTemplates.all
        .filter { isPhoneOnly($0.kind) }
        .flatMap(\.signals)
        .filter { $0.1 >= decisiveWeight }
        .map(\.0)
        .reduce(into: []) { words, word in if !words.contains(word) { words.append(word) } }

    /// The weight from which a template's word decides the kind by itself.
    static let decisiveWeight = 4.0

    static func hasDecisiveWords(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let folded = RomanianText.fold(text)
        return decisiveWords.contains { CaptureText.containsWord($0, inFolded: folded) }
    }
}
