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
        .birthDate, .sex, .personalNumber, .issueDate, .expiryDate, .issuer,
    ]

    /// Whether a field may appear on this kind of document.
    func allows(_ key: CaptureFieldKey) -> Bool {
        switch self {
        case .passport, .identityCard:
            return Self.identityKeys.contains(key)
        case .drivingLicence:
            return Self.identityKeys.contains(key) || key == .licenceCategories
        default:
            return !Self.personalKeys.contains(key)
        }
    }

    /// The fields a document of this kind usually carries, beyond identity documents
    /// (whose fields come from their templates in `IdentityTemplates`). A cloud model is
    /// asked for exactly these (`CloudSchema`).
    var expectedKeys: [CaptureFieldKey] {
        switch self {
        case .passport, .identityCard, .drivingLicence:
            IdentityTemplates.all.filter { $0.kind == self }.flatMap { $0.fields.map(\.key) }
        case .vehicleRegistration: [.licensePlate, .vin, .make, .model, .firstRegistrationDate]
        case .rcaPolicy: [.provider, .policyNumber, .startDate, .expiryDate, .total, .claimsPhone, .licensePlate, .vin, .bonusMalusClass]
        case .insurancePolicy: [.provider, .policyNumber, .startDate, .expiryDate, .total, .claimsPhone, .licensePlate]
        case .utilityInvoice: [.provider, .invoiceNumber, .issueDate, .dueDate, .total, .clientCode, .podCode, .clcCode, .meterIndex]
        case .serviceInvoice: [.provider, .invoiceNumber, .issueDate, .total, .licensePlate, .vin, .odometer, .lineItems]
        case .fiscalReceipt: [.retailer, .purchaseDate, .purchasePrice, .productName, .serialNumber, .lineItems]
        case .warrantyCertificate: [.retailer, .productName, .serialNumber, .purchaseDate, .warrantyMonths, .warrantyUntil]
        case .itpReport: [.provider, .licensePlate, .vin, .issueDate, .expiryDate, .odometer]
        case .veterinaryRecord: [.provider, .petName, .microchip, .vaccineName, .issueDate, .nextDoseDate]
        case .medicalResult: [.provider, .issueDate]
        case .other: [.provider, .documentNumber, .invoiceNumber, .issueDate, .dueDate, .expiryDate, .total]
        }
    }

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
