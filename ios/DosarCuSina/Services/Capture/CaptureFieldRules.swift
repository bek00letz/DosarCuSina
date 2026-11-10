import Foundation

/// Which fields belong on which kind of document, applied after every tier
/// (patterns, on-device model, Gemini), so no tier can put a field where it
/// doesn't belong: an ID card has no line items or totals, and an invoice never
/// carries a personal number, birth date or sex.
extension CaptureDocumentKind {

    /// Fields that identify a person. Only personal documents may carry them.
    static let personalKeys: Set<CaptureFieldKey> = [.personalNumber, .birthDate, .sex, .nationality]

    /// Whether a field may appear on this kind of document (`CaptureKindProfile.allows`).
    func allows(_ key: CaptureFieldKey) -> Bool { profile.allows(key) }

    /// Fields only bills and contracts carry: where the service is supplied and whether
    /// the bank pays it. A policy or a receipt has neither, whatever a model reads into it.
    static let subscriptionKeys: Set<CaptureFieldKey> = [.supplyAddress, .directDebit]

    /// Fields only a policy carries: who it insures and their bonus-malus class.
    static let policyholderKeys: Set<CaptureFieldKey> = [.policyholder, .policyholderPersonalNumber, .bonusMalusClass]

    /// Fields only personal documents carry: what a cazier says, a bank card's network and
    /// last four digits.
    static let personalDocumentKeys: Set<CaptureFieldKey> = [.recordResult, .cardNetwork, .cardLastFour]

    /// The longest description a line item can have; anything longer is prose
    /// (terms, consent clauses), not something done or bought.
    static let lineItemMaxLength = 90

    /// Keeps only lines that look like lines: a short description with letters, and
    /// an amount above zero or a part the catalog knows.
    static func realLineItems(_ items: [CaptureLineItem]) -> [CaptureLineItem] {
        items.filter { item in
            let description = item.description.trimmingCharacters(in: .whitespacesAndNewlines)
            guard description.count <= lineItemMaxLength, description.contains(where: \.isLetter) else { return false }
            return (item.amount?.amount ?? 0) > 0 || item.componentKey != nil
        }
    }

    /// The fields a document of this kind usually carries, from its profile (identity
    /// documents' come from their templates in `IdentityTemplates`). Both language models
    /// are asked for these (`ModelQuestions`), and every one is kept (`allows`).
    var expectedKeys: [CaptureFieldKey] { profile.expectedKeys }

    /// Fields that, found by the pattern tiers with good confidence, make the on-device
    /// model unnecessary: the profile's (`CaptureKindProfile.essentialKeys`).
    var essentialKeys: [CaptureFieldKey] { profile.essentialKeys }

    /// Whether a reading of this kind has none of the fields it should carry: for an
    /// identity document, not one of its essentials, its personal number or birth date.
    /// Such a reading is retried with another view of the photo.
    func lacksExpectedFields(_ fields: [CaptureField]) -> Bool {
        guard isIdentityDocument else { return false }
        let expected = Set(essentialKeys + [.personalNumber, .birthDate, .givenNames])
        return !fields.contains { expected.contains($0.key) }
    }

    /// Whether the patterns already read everything that matters on this document.
    func isComplete(_ fields: [CaptureField], minimumConfidence: Double = 0.6) -> Bool {
        let keys = essentialKeys
        guard !keys.isEmpty else { return false }
        return keys.allSatisfy { key in fields.contains { $0.key == key && $0.confidence >= minimumConfidence } }
    }
}

extension CaptureKindProfile {
    /// Whether a field may be kept on a document of this kind, decided from the profile
    /// alone, so what a kind is asked and what it keeps can't disagree:
    /// - every field it is asked for (`expectedKeys`) is kept;
    /// - a personal document keeps only what its templates read, what its machine-readable
    ///   zone gives when its templates have one, its holder and its variant: a bank card has
    ///   no CNP, a cazier no total, an identity card no line items;
    /// - any other kind keeps what belongs to no other family: never a person's own data
    ///   or a personal document's; lines only when it lists what was done or bought; who a
    ///   policy insures only on a policy; the supply address and direct debit only on a
    ///   subscription's paper; and one number of its own (`numberKey`: a policy's is its
    ///   policy number, never a second "Serie și număr" beside it).
    func allows(_ key: CaptureFieldKey) -> Bool {
        if expectedKeys.contains(key) { return true }
        if documentType != nil { return personalDocumentFields.contains(key) }
        if key == .lineItems { return carriesLineItems }
        if CaptureDocumentKind.policyholderKeys.contains(key) { return readsCover }
        if key == .documentNumber { return numberKey == .documentNumber }
        if CaptureDocumentKind.subscriptionKeys.contains(key) { return filing == .subscription }
        return !CaptureDocumentKind.personalKeys.contains(key) && !CaptureDocumentKind.personalDocumentKeys.contains(key)
    }

    /// What a personal document keeps besides what it is asked: what its templates read, its
    /// machine-readable zone's values when its templates read one, its holder and variant.
    private var personalDocumentFields: Set<CaptureFieldKey> {
        var keys = IdentityTemplates.fieldKeys(for: kind).union([.holderName, .documentVariant])
        if IdentityTemplates.all.contains(where: { $0.kind == kind && !$0.machineReadableFormats.isEmpty }) {
            keys.formUnion(CaptureAnalyzer.machineReadableKeys)
        }
        return keys
    }
}
