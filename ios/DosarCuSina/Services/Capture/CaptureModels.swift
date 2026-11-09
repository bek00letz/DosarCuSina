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
    /// A criminal record certificate: judiciar, fiscal or auto (`DocumentType.Variant`).
    case criminalRecord
    /// A health insurance card: the European one (the card's printed fields are set by
    /// the EU and by CNAS), or the national one.
    case healthInsuranceCard
    /// A bank card. Only its bank, network, kind, last four digits and expiry are kept;
    /// its full number never is (`PaymentCardNumbers`).
    case bankCard
    case vehicleRegistration
    case rcaPolicy
    case insurancePolicy
    case utilityInvoice
    /// A contract for an ongoing service (gas, electricity, water, internet and TV, a
    /// mobile plan) or an addendum to one: who provides it, from when, for how long.
    case contract
    case serviceInvoice
    case fiscalReceipt
    case warrantyCertificate
    case itpReport
    case veterinaryRecord
    case medicalResult
    case other

    /// Identity documents hold personal data and belong in a sensitive category by default.
    /// Only these carry a machine-readable zone, a back to add and the essentials a weak
    /// reading is judged by.
    public var isIdentityDocument: Bool {
        switch self {
        case .passport, .identityCard, .drivingLicence: true
        default: false
        }
    }

    /// A document of its holder's, filed under them in the personal documents category
    /// and named after them: an identity document, a cazier, a health card, a bank card.
    /// Its kind profile names its document type; its fields come from its templates.
    public var isPersonalDocument: Bool {
        profile.documentType != nil
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
    /// A meter reading such as an odometer: `value` in `unit` (kilometres, engine hours, m³).
    case metric(value: Decimal, unit: MeasurementUnit)
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
    /// The AI provider the person set up with their own key: when they ask for it, or
    /// automatically when they chose so and the phone's reading is weak.
    case cloudModel

    /// The readers in the order `ReadingArbiter` trusts them when no check decides:
    /// lower comes first. The full order, checks included, is in `ReadingArbiter`.
    var rank: Int {
        switch self {
        case .deterministic: 0
        case .cloudModel: 1
        case .heuristic: 2
        case .onDeviceModel: 3
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
    /// What a criminal record certificate says, as printed: "Nu figurează în cazierul judiciar".
    public static let recordResult: CaptureFieldKey = "recordResult"

    // Bank cards: never the full number.
    /// The last four digits of a bank card's number, and nothing more.
    public static let cardLastFour: CaptureFieldKey = "cardLastFour"
    /// The card's network, as a `PaymentCardNetwork` key.
    public static let cardNetwork: CaptureFieldKey = "cardNetwork"

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
    /// The series and number of the vehicle's identity card (CIV), as one value: "J123456".
    public static let civNumber: CaptureFieldKey = "civNumber"

    // Utilities
    public static let clientCode: CaptureFieldKey = "clientCode"
    public static let podCode: CaptureFieldKey = "podCode"
    public static let clcCode: CaptureFieldKey = "clcCode"
    public static let meterIndex: CaptureFieldKey = "meterIndex"

    // Ongoing contracts (bills and the contracts themselves)
    /// What the contract is for, as a `ServiceKind` key ("service.gas").
    public static let serviceKind: CaptureFieldKey = "serviceKind"
    public static let contractNumber: CaptureFieldKey = "contractNumber"
    /// The subscriber's own phone number on a mobile plan.
    public static let phoneNumber: CaptureFieldKey = "phoneNumber"
    /// How many months the person committed to ("perioada minimă").
    public static let minimumMonths: CaptureFieldKey = "minimumMonths"
    /// The last day of the minimum period.
    public static let minimumPeriodEnd: CaptureFieldKey = "minimumPeriodEnd"
    /// The price per month the contract states.
    public static let monthlyPrice: CaptureFieldKey = "monthlyPrice"
    /// Where the service is supplied ("Adresa locului de consum"), as printed. Never the
    /// payer's billing address.
    public static let supplyAddress: CaptureFieldKey = "supplyAddress"
    /// The bill says the bank pays it by direct debit: the statement as printed ("Factura
    /// se achită prin debit direct"). Only a suggestion; the person turns it on.
    public static let directDebit: CaptureFieldKey = "directDebit"

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
             .clientCode, .contractNumber, .phoneNumber, .microchip, .documentNumber, .serialNumber:
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
    /// An AI provider's value has a high confidence only when it passed its own check or
    /// agrees with what the phone read (`CloudAnswerMapper`), and one that replaced a
    /// different phone value is marked too (`ReadingArbiter`); otherwise its low
    /// confidence marks it here.
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
        /// Create a new asset from a template of the binder's catalog (`vehicle`, `documents`, `purchase`).
        case newAsset(templateKey: String)
        /// Add or update an obligation from a blueprint of that template (`vehicle.rca`, `document.renew`).
        case obligation(blueprintKey: String, templateKey: String?)
        /// Log what happened in the asset's history (a service visit, a bill, a vaccine).
        case historyEntry(templateKey: String?)
        /// Remember who did the work or issued the document; `trade` is a `ProviderTrade` raw value.
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

/// The deadline the date on this document sets. How early it reminds is the blueprint's
/// (`ObligationBlueprint.reminders`), never capture's.
public struct CaptureReminderHint: Hashable, Codable, Sendable {
    /// The day that matters (expiry, due date, next dose).
    public let day: CaptureDay
    /// The deadline, as a blueprint of the binder's catalog: `vehicle.rca`, `document.renew`.
    public let blueprintKey: String
    /// The category whose blueprint it is.
    public let templateKey: String

    public init(day: CaptureDay, blueprintKey: String, templateKey: String) {
        self.day = day
        self.blueprintKey = blueprintKey
        self.templateKey = templateKey
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
    /// The cloud model was asked for, but what the phone read may be a document read only
    /// on the phone (`PhoneOnlyReading`: a bank card), so nothing was sent.
    case readOnPhoneOnly
    /// Only the first pages of a long PDF were read.
    case pagesTruncated(readPages: Int, totalPages: Int)
    /// An identity card read from one photo without its machine-readable zone: the
    /// back carries the zone that confirms the values.
    case identityBackMissing
    /// A value was dropped or marked for a look because it fell outside its plausible
    /// window or disagreed with another (a birth date read as the issue date). Part of
    /// what makes a reading weak (`ReadingArbiter.weaknesses`); the review marks the values.
    case valueFailedCheck
}

/// A barcode or QR code found on the page.
public struct CaptureBarcode: Hashable, Codable, Sendable {
    public let symbology: String
    public let payload: String

    public init(symbology: String, payload: String) {
        self.symbology = symbology
        self.payload = payload
    }

    /// The long digit codes Romanian utilities print as payment barcodes (25 to 50 digits),
    /// decoded from the page. Evidence that the document is a bill.
    public var isPaymentCode: Bool {
        (25...50).contains(payload.count) && payload.allSatisfy(\.isASCIIDigit)
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}

// MARK: - Evidence and alternatives

/// What the document's kind rests on. `ReadingArbiter` lets a second opinion replace the
/// phone's kind unless it rests on deterministic evidence.
public enum CaptureKindEvidence: String, Codable, Sendable, CaseIterable {
    /// A machine-readable zone whose check digits all pass.
    case machineReadableZone
    /// A provider's known format (a utility's bill layout) that the classifier agrees with.
    case providerFormat
    /// A payment barcode decoded from a bill.
    case paymentBarcode
    /// The classifier's weighted keywords (or a zone whose check digits failed).
    case classifier
    /// A provider's known format the classifier didn't independently support.
    case providerFormatAlone
    /// Apple's on-device model corrected an unsure classifier.
    case onDeviceModel
    /// The person's AI provider, reading the page as a second opinion.
    case secondOpinion

    /// Evidence no reading can argue with: only a check or a decoded code.
    public var isDeterministic: Bool {
        switch self {
        case .machineReadableZone, .providerFormat, .paymentBarcode: true
        default: false
        }
    }
}

/// Who read a value or a kind that wasn't kept, so the review can offer it beside the
/// one shown, with "Folosește-l".
public enum CaptureAlternativeSource: Hashable, Codable, Sendable {
    /// The phone's own reading: patterns, labels or Apple's on-device model.
    case phone
    /// The person's AI provider.
    case cloudModel
    /// A value proven by its own check: the machine-readable zone's check digits, or
    /// another control digit (a CNP's, a VIN's, a CUI's).
    case checked(machineReadable: Bool)
}

/// A reading that wasn't kept, offered beside the one shown and never applied by itself.
public struct CaptureAlternative<Value: Hashable & Codable & Sendable>: Hashable, Codable, Sendable {
    public let value: Value
    public let source: CaptureAlternativeSource

    public init(_ value: Value, source: CaptureAlternativeSource) {
        self.value = value
        self.source = source
    }
}

/// A field's value that another reader read differently.
public struct CaptureFieldAlternative: Hashable, Codable, Sendable {
    public let key: CaptureFieldKey
    public let alternative: CaptureAlternative<CaptureValue>

    public init(key: CaptureFieldKey, alternative: CaptureAlternative<CaptureValue>) {
        self.key = key
        self.alternative = alternative
    }
}

// MARK: - Result

/// What the readers read from the pages, before deciding the kind's fields: the text
/// with its layout, the codes, and the models' answers. Reading it again as another
/// kind needs nothing else.
public struct CaptureReadingSource: Sendable, Codable, Hashable {
    /// The recognized text, as read.
    public let text: String
    /// Recognized lines with their positions, page by page. Empty for pasted text and a PDF's text layer.
    public let pages: [[RecognizedLine]]
    public let barcodes: [CaptureBarcode]
    /// "Today" when it was read, for the windows dates must fall in.
    public let referenceDate: Date
    /// Apple's on-device model's answers.
    public let modelFields: [CaptureField]
    /// The person's AI provider's answers, when it read the page.
    public let aiFields: [CaptureField]?
    /// One photo of the page: an identity card read from it alone asks for its back.
    public let isSinglePhoto: Bool

    public init(text: String, pages: [[RecognizedLine]], barcodes: [CaptureBarcode], referenceDate: Date,
                modelFields: [CaptureField], aiFields: [CaptureField]?, isSinglePhoto: Bool) {
        self.text = text
        self.pages = pages
        self.barcodes = barcodes
        self.referenceDate = referenceDate
        self.modelFields = modelFields
        self.aiFields = aiFields
        self.isSinglePhoto = isSinglePhoto
    }
}

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
    /// The document this capture is about: its pages waiting in the document store,
    /// or the copy the binder already keeps. Nil when nothing was stored (pasted text).
    public let document: CapturedDocumentRef?
    public let notices: [CaptureNotice]
    /// What the kind rests on.
    public let kindEvidence: CaptureKindEvidence
    /// Kinds another reader saw (the phone's, when the AI's replaced it).
    public let kindAlternatives: [CaptureAlternative<CaptureDocumentKind>]
    /// Values another reader read differently from the ones kept.
    public let fieldAlternatives: [CaptureFieldAlternative]
    /// Whether the person's AI provider read the page and answered.
    public let readWithCloudModel: Bool
    /// What the readers read, kept so the page can be read again as another kind
    /// (`CaptureEngine.reinterpret`) without new pictures. Nil for a hand-made result.
    public let source: CaptureReadingSource?

    public init(
        id: UUID = UUID(),
        kind: CaptureDocumentKind,
        kindConfidence: Double,
        fields: [CaptureField],
        suggestions: [CaptureSuggestion],
        reminder: CaptureReminderHint?,
        recognizedText: String,
        barcodes: [CaptureBarcode],
        document: CapturedDocumentRef?,
        notices: [CaptureNotice],
        kindEvidence: CaptureKindEvidence = .classifier,
        kindAlternatives: [CaptureAlternative<CaptureDocumentKind>] = [],
        fieldAlternatives: [CaptureFieldAlternative] = [],
        readWithCloudModel: Bool = false,
        source: CaptureReadingSource? = nil
    ) {
        self.id = id
        self.kind = kind
        self.kindConfidence = kindConfidence
        self.fields = fields
        self.suggestions = suggestions
        self.reminder = reminder
        self.recognizedText = recognizedText
        self.barcodes = barcodes
        self.document = document
        self.notices = notices
        self.kindEvidence = kindEvidence
        self.kindAlternatives = kindAlternatives
        self.fieldAlternatives = fieldAlternatives
        self.readWithCloudModel = readWithCloudModel
        self.source = source
    }

    /// The best field for a key.
    public func field(_ key: CaptureFieldKey) -> CaptureField? {
        fields.first { $0.key == key }
    }

    /// What other readers read for a key, beside the value kept.
    public func alternatives(for key: CaptureFieldKey) -> [CaptureAlternative<CaptureValue>] {
        fieldAlternatives.filter { $0.key == key }.map(\.alternative)
    }

    /// Who decided the kind shown: the AI when its second opinion replaced or confirmed it.
    public var kindSource: CaptureAlternativeSource {
        switch kindEvidence {
        case .secondOpinion: .cloudModel
        case .machineReadableZone: .checked(machineReadable: true)
        default: .phone
        }
    }

    /// Which tiers contributed at least one field.
    public var tiersUsed: Set<CaptureTier> {
        Set(fields.map(\.tier))
    }
}
