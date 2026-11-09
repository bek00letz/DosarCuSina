import Foundation

/// Which fields belong on which kind of document, applied after every tier
/// (patterns, on-device model, Gemini), so no tier can put a field where it
/// doesn't belong: an ID card has no line items or totals, and an invoice never
/// carries a personal number, birth date or sex.
extension CaptureDocumentKind {

    /// Fields that identify a person. Only identity documents may carry them.
    static let personalKeys: Set<CaptureFieldKey> = [.personalNumber, .birthDate, .sex, .nationality]

    /// Fields printed on identity documents.
    static let identityKeys: Set<CaptureFieldKey> = [
        .documentNumber, .documentCode, .issuingCountry, .nationality, .surname, .givenNames, .holderName,
        .birthDate, .sex, .personalNumber, .issueDate, .expiryDate, .issuer, .documentVariant,
    ]

    /// Whether a field may appear on this kind of document. Only kinds whose profile lists
    /// what was done or bought carry lines: a policy, a utility bill or a report has no
    /// "Ce s-a făcut", whatever a model reads into it.
    func allows(_ key: CaptureFieldKey) -> Bool {
        switch self {
        case .passport, .identityCard:
            return Self.identityKeys.contains(key)
        case .drivingLicence:
            return Self.identityKeys.contains(key) || key == .licenceCategories
        case _ where isPersonalDocument:
            // Another personal document carries what its templates read, its holder and its
            // variant, and nothing else: a bank card has no CNP, a cazier no total.
            return IdentityTemplates.fieldKeys(for: self).contains(key) || key == .holderName || key == .documentVariant
        default:
            if key == .lineItems { return profile.carriesLineItems }
            // Who a policy insures, and their class, only on a policy.
            if Self.policyholderKeys.contains(key) { return profile.readsCover }
            // A document carries one number of its own: a policy's is its policy number, never
            // a second "Serie și număr" beside it (`CompositeValue.reconcile` folds one in).
            if key == .documentNumber { return profile.numberKey == .documentNumber }
            if Self.subscriptionKeys.contains(key) { return profile.filing == .subscription }
            return !Self.personalKeys.contains(key) && !Self.personalDocumentKeys.contains(key)
        }
    }

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
    /// documents' come from their templates in `IdentityTemplates`). A cloud model is
    /// asked for exactly these (`CloudSchema`).
    var expectedKeys: [CaptureFieldKey] { profile.expectedKeys }

    /// Fields that, found by the pattern tiers with good confidence, make the
    /// on-device model unnecessary. Empty means the model always helps.
    var essentialKeys: [CaptureFieldKey] {
        switch self {
        case .passport, .identityCard, .drivingLicence: [.surname, .documentNumber, .expiryDate]
        default: []
        }
    }

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
