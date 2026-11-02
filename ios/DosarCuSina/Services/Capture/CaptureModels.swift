import Foundation

// The value types every capture produces. They don't depend on the app's
// SwiftData models, so the same pipeline can run in the app, in a Share
// Extension, or in a test, and Core's model layer adopts the result at the edge.

// MARK: - Document kind

/// What kind of paper or file the capture looks like.
public enum CaptureDocumentKind: String, Codable, Sendable, CaseIterable {
    case passport
    case identityCard
    case drivingLicence
    case vehicleRegistration
    case rcaPolicy
    case insurancePolicy
    case utilityInvoice
    case serviceInvoice
    case fiscalReceipt
    case warrantyCertificate
    case itpReport
    case veterinaryRecord
    case medicalResult
    case other

    /// Identity documents hold personal data and belong in a sensitive category by default.
    public var isIdentityDocument: Bool {
        switch self {
        case .passport, .identityCard, .drivingLicence: true
        default: false
        }
    }
}

// MARK: - Values

/// A calendar day with no time and no time zone.
///
/// Expiry and due dates are days, not instants. Storing them as `Date` invites
/// off-by-one bugs when the time zone changes, so the pipeline keeps them as days
/// and converts at the edge with ``date(in:)``.
public struct CaptureDay: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Returns `nil` for impossible days such as 31 February.
    public init?(year: Int, month: Int, day: Int) {
        guard (1...12).contains(month), day >= 1, year >= 1900, year <= 2200 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.day, from: date) == day,
              calendar.component(.month, from: date) == month else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    public init(date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        // A Gregorian date always has these components.
        self.year = parts.year ?? 1970
        self.month = parts.month ?? 1
        self.day = parts.day ?? 1
    }

    /// Midnight at the start of this day in the given calendar.
    public func date(in calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// Adds whole months, clamping to the last day of a shorter month (31 Jan + 1 month = 28/29 Feb).
    public func addingMonths(_ months: Int) -> CaptureDay? {
        let total = (year * 12 + (month - 1)) + months
        let newYear = total / 12
        let newMonth = total % 12 + 1
        var clampedDay = day
        while clampedDay > 27 {
            if let result = CaptureDay(year: newYear, month: newMonth, day: clampedDay) { return result }
            clampedDay -= 1
        }
        return CaptureDay(year: newYear, month: newMonth, day: clampedDay)
    }

    public static func < (lhs: CaptureDay, rhs: CaptureDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// ISO 8601 calendar date, e.g. `2031-03-12`.
    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

/// An amount of money in one currency. Never added across currencies.
public struct CaptureMoney: Hashable, Codable, Sendable {
    public let amount: Decimal
    /// ISO 4217 code, e.g. `RON`, `EUR`.
    public let currencyCode: String

    public init(amount: Decimal, currencyCode: String) {
        self.amount = amount
        self.currencyCode = currencyCode
    }
}

/// One line of an invoice or receipt: a part, a service, or labour.
public struct CaptureLineItem: Hashable, Codable, Sendable {
    public let description: String
    public let quantity: Decimal?
    public let amount: CaptureMoney?
    /// The catalog component guessed from the description (e.g. `brakes.padsFront`), if any.
    public let componentKey: String?
    /// Whether the line is labour rather than a part.
    public let isLabour: Bool

    public init(description: String, quantity: Decimal? = nil, amount: CaptureMoney? = nil, componentKey: String? = nil, isLabour: Bool? = nil) {
        self.description = description
        self.quantity = quantity
        self.amount = amount
        self.componentKey = componentKey
        self.isLabour = isLabour ?? LabourLine.matches(description)
    }
}

/// A typed field value.
public enum CaptureValue: Hashable, Codable, Sendable {
    case text(String)
    case day(CaptureDay)
    case money(CaptureMoney)
    case number(Decimal)
    /// A meter reading such as an odometer: `value` in `unit` (`km`, `h`, `kWh`, `mc`).
    case metric(value: Decimal, unit: String)
    case lineItems([CaptureLineItem])

    public var text: String? { if case .text(let value) = self { value } else { nil } }
    public var day: CaptureDay? { if case .day(let value) = self { value } else { nil } }
    public var money: CaptureMoney? { if case .money(let value) = self { value } else { nil } }
    public var lineItems: [CaptureLineItem]? { if case .lineItems(let value) = self { value } else { nil } }
}

// MARK: - Fields

/// Where a field came from, from most to least certain.
public enum CaptureTier: String, Codable, Sendable, CaseIterable, Comparable {
    /// Verified structure: an MRZ check digit, a barcode payload, a CUI checksum, a known provider format.
    case deterministic
    /// Patterns and labels in the recognized text.
    case heuristic
    /// Apple's on-device language model. Private and offline.
    case onDeviceModel
    /// The AI provider the person set up with their own key, only when they ask for it.
    case cloudModel

    /// Lower rank wins when two tiers disagree about the same field.
    var rank: Int {
        switch self {
        case .deterministic: 0
        case .onDeviceModel: 1
        case .cloudModel: 2
        case .heuristic: 3
        }
    }

    public static func < (lhs: CaptureTier, rhs: CaptureTier) -> Bool { lhs.rank < rhs.rank }
}

/// The role a field can play once it lands on an asset. Raw values match Core's field roles.
public enum CaptureFieldRole: String, Codable, Sendable {
    case keyFact
    case purchaseDate
    case purchasePrice
    case retailer
    case warrantyUntil
    case expiry
    case title
}

/// A stable field identifier. Keys are plain strings so they survive the `.dosar`
/// archive and can be read on any platform.
public struct CaptureFieldKey: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public var description: String { rawValue }

    // Identity documents
    public static let documentNumber: CaptureFieldKey = "documentNumber"
    public static let documentCode: CaptureFieldKey = "documentCode"
    public static let issuingCountry: CaptureFieldKey = "issuingCountry"
    public static let nationality: CaptureFieldKey = "nationality"
    public static let surname: CaptureFieldKey = "surname"
    public static let givenNames: CaptureFieldKey = "givenNames"
    public static let holderName: CaptureFieldKey = "holderName"
    public static let birthDate: CaptureFieldKey = "birthDate"
    public static let sex: CaptureFieldKey = "sex"
    public static let personalNumber: CaptureFieldKey = "personalNumber"
    public static let licenceCategories: CaptureFieldKey = "licenceCategories"
    /// Which variant of its document type this is (a `DocumentType.Variant` key), from the matched layout.
    public static let documentVariant: CaptureFieldKey = "documentVariant"

    // Validity
    public static let issueDate: CaptureFieldKey = "issueDate"
    public static let startDate: CaptureFieldKey = "startDate"
    public static let expiryDate: CaptureFieldKey = "expiryDate"
    public static let dueDate: CaptureFieldKey = "dueDate"
    public static let issuer: CaptureFieldKey = "issuer"

    // Money and providers
    public static let provider: CaptureFieldKey = "provider"
    public static let providerTaxID: CaptureFieldKey = "providerTaxID"
    public static let providerPhone: CaptureFieldKey = "providerPhone"
    public static let total: CaptureFieldKey = "total"
    public static let lineItems: CaptureFieldKey = "lineItems"
    public static let invoiceNumber: CaptureFieldKey = "invoiceNumber"
    public static let paymentCode: CaptureFieldKey = "paymentCode"

    // Insurance
    public static let policyNumber: CaptureFieldKey = "policyNumber"
    public static let claimsPhone: CaptureFieldKey = "claimsPhone"
    public static let coverageType: CaptureFieldKey = "coverageType"
    public static let bonusMalusClass: CaptureFieldKey = "bonusMalusClass"

    // Vehicles
    public static let licensePlate: CaptureFieldKey = "licensePlate"
    public static let vin: CaptureFieldKey = "vin"
    public static let make: CaptureFieldKey = "make"
    public static let model: CaptureFieldKey = "model"
    public static let firstRegistrationDate: CaptureFieldKey = "firstRegistrationDate"
    public static let odometer: CaptureFieldKey = "odometer"

    // Utilities
    public static let clientCode: CaptureFieldKey = "clientCode"
    public static let podCode: CaptureFieldKey = "podCode"
    public static let clcCode: CaptureFieldKey = "clcCode"
    public static let meterIndex: CaptureFieldKey = "meterIndex"

    // Purchases and warranties
    public static let productName: CaptureFieldKey = "productName"
    public static let serialNumber: CaptureFieldKey = "serialNumber"
    public static let retailer: CaptureFieldKey = "retailer"
    public static let purchaseDate: CaptureFieldKey = "purchaseDate"
    public static let purchasePrice: CaptureFieldKey = "purchasePrice"
    public static let warrantyMonths: CaptureFieldKey = "warrantyMonths"
    public static let warrantyUntil: CaptureFieldKey = "warrantyUntil"

    // Pets and health
    public static let petName: CaptureFieldKey = "petName"
    public static let microchip: CaptureFieldKey = "microchip"
    public static let vaccineName: CaptureFieldKey = "vaccineName"
    public static let nextDoseDate: CaptureFieldKey = "nextDoseDate"

    /// The asset-field role this key maps to, if it has one.
    public var role: CaptureFieldRole? {
        switch self {
        case .policyNumber, .claimsPhone, .vin, .licensePlate, .podCode, .clcCode,
             .clientCode, .microchip, .documentNumber, .serialNumber:
            .keyFact
        case .purchaseDate: .purchaseDate
        case .purchasePrice: .purchasePrice
        case .retailer: .retailer
        case .warrantyUntil: .warrantyUntil
        case .expiryDate: .expiry
        case .productName: .title
        default: nil
        }
    }
}

/// One extracted fact, with how sure we are and where it came from.
public struct CaptureField: Hashable, Codable, Sendable {
    public let key: CaptureFieldKey
    public let value: CaptureValue
    /// 0…1. Deterministic, checksum-verified fields are close to 1.
    public let confidence: Double
    /// The text the value was read from, so the review screen can show it.
    public let sourceText: String?
    public let tier: CaptureTier

    public init(key: CaptureFieldKey, value: CaptureValue, confidence: Double, sourceText: String? = nil, tier: CaptureTier) {
        self.key = key
        self.value = value
        self.confidence = min(max(confidence, 0), 1)
        self.sourceText = sourceText
        self.tier = tier
    }

    /// The source text of values read from the machine-readable zone.
    public static let machineReadableSource = "MRZ"

    /// Whether a person should look at this value before it is saved: it failed a
    /// format or a cross-check (low confidence), or only the on-device model read it.
    /// A cloud provider's value is kept with a high confidence only when it is grounded
    /// in the recognized text or passed its own check (`CloudAnswerMapper`); otherwise
    /// its low confidence marks it here.
    public var needsCheck: Bool {
        confidence < Self.checkThreshold || tier == .onDeviceModel
    }

    /// Below this, a value is marked for a check.
    public static let checkThreshold = 0.6
}

// MARK: - Suggestions

/// A value that can identify an existing asset, e.g. a plate or a POD code.
public struct CaptureAssetHint: Hashable, Codable, Sendable {
    public let key: CaptureFieldKey
    public let value: String

    public init(key: CaptureFieldKey, value: String) {
        self.key = key
        self.value = value
    }
}

/// Where the captured information could go. The user confirms; nothing is saved automatically.
public struct CaptureSuggestion: Hashable, Codable, Sendable {
    public enum Destination: Hashable, Codable, Sendable {
        /// Create a new asset from a template (`vehicle`, `home`, `pet`, `health`, `documents`, `warranties`, `subscriptions`).
        case newAsset(templateKey: String)
        /// Add or update an obligation from a blueprint (e.g. `rca`, `itp`, `passportRenewal`).
        case obligation(blueprintKey: String, templateKey: String?)
        /// Log what happened in the asset's history (a service visit, a bill, a vaccine).
        case historyEntry(templateKey: String?)
        /// Remember who did the work or issued the document.
        case provider(name: String, trade: String?)
        /// Keep the document on file without creating anything else.
        case attachOnly
    }

    public let destination: Destination
    /// Values that can find an existing asset to attach to.
    public let assetHints: [CaptureAssetHint]
    public let confidence: Double

    public init(destination: Destination, assetHints: [CaptureAssetHint] = [], confidence: Double) {
        self.destination = destination
        self.assetHints = assetHints
        self.confidence = min(max(confidence, 0), 1)
    }
}

/// How early to warn about the date this document carries.
public struct CaptureReminderHint: Hashable, Codable, Sendable {
    /// The day that matters (expiry, due date, next dose).
    public let day: CaptureDay
    /// The reminder profile Core should apply, e.g. `passport`, `rca`, `petVaccine`.
    public let profileKey: String
    /// Days before ``day`` to warn, longest first. A fallback when Core has no profile for the key.
    public let leadDays: [Int]

    public init(day: CaptureDay, profileKey: String, leadDays: [Int]) {
        self.day = day
        self.profileKey = profileKey
        self.leadDays = leadDays.sorted(by: >)
    }
}

/// Something the review screen should mention.
public enum CaptureNotice: Hashable, Codable, Sendable {
    /// A machine-readable zone was found, but a check digit didn't match. Fields from it need a look.
    case machineReadableZoneUnverified
    /// The photo was hard to read, even after a retry with another view of it: very
    /// little text, or an identity document without its main fields. A new photo,
    /// straight and without glare, would help.
    case littleTextRecognized
    /// The on-device model isn't available, so only patterns were used.
    case onDeviceModelUnavailable(reason: String)
    /// The on-device model ran but failed.
    case onDeviceModelFailed
    /// The cloud model was asked for but couldn't run.
    case cloudModelFailed(reason: String)
    /// The same document was captured before.
    case duplicateDocument(documentID: UUID)
    /// Only the first pages of a long PDF were read.
    case pagesTruncated(readPages: Int, totalPages: Int)
    /// An identity card read from one photo without its machine-readable zone: the
    /// back carries the zone that confirms the values.
    case identityBackMissing
}

/// A barcode or QR code found on the page.
public struct CaptureBarcode: Hashable, Codable, Sendable {
    public let symbology: String
    public let payload: String

    public init(symbology: String, payload: String) {
        self.symbology = symbology
        self.payload = payload
    }
}

// MARK: - Result

/// Everything one capture produced. A draft for the user to confirm, never saved by itself.
public struct CaptureResult: Sendable, Codable, Hashable {
    public let id: UUID
    public let kind: CaptureDocumentKind
    public let kindConfidence: Double
    public let fields: [CaptureField]
    public let suggestions: [CaptureSuggestion]
    public let reminder: CaptureReminderHint?
    public let recognizedText: String
    public let barcodes: [CaptureBarcode]
    /// The stored document, when the capture was saved to the document store.
    public let documentID: UUID?
    public let notices: [CaptureNotice]

    public init(
        id: UUID = UUID(),
        kind: CaptureDocumentKind,
        kindConfidence: Double,
        fields: [CaptureField],
        suggestions: [CaptureSuggestion],
        reminder: CaptureReminderHint?,
        recognizedText: String,
        barcodes: [CaptureBarcode],
        documentID: UUID?,
        notices: [CaptureNotice]
    ) {
        self.id = id
        self.kind = kind
        self.kindConfidence = kindConfidence
        self.fields = fields
        self.suggestions = suggestions
        self.reminder = reminder
        self.recognizedText = recognizedText
        self.barcodes = barcodes
        self.documentID = documentID
        self.notices = notices
    }

    /// The best field for a key.
    public func field(_ key: CaptureFieldKey) -> CaptureField? {
        fields.first { $0.key == key }
    }

    /// Which tiers contributed at least one field.
    public var tiersUsed: Set<CaptureTier> {
        Set(fields.map(\.tier))
    }
}
