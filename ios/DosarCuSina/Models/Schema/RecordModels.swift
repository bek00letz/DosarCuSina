import CryptoKit
import Foundation
import SwiftData

/// What a measurement reads. Raw values are part of the `.dosar` contract.
public enum MeasurementKind: String, Codable, CaseIterable, Sendable {
    case electricity
    case gas
    case coldWater
    case hotWater
    case thermalEnergy
    case biomarker
    case bloodPressure
    case bodyWeight
    case diopters
    case odometer
    case engineHours
    case cycles
    case custom

    /// The unit a reading of this kind is in when nothing says otherwise; nil when it has none.
    public var defaultUnit: MeasurementUnit? {
        switch self {
        case .electricity: return .kilowattHours
        case .gas, .coldWater, .hotWater: return .cubicMetres
        case .thermalEnergy: return .gigacalories
        case .biomarker: return .milligramsPerDecilitre
        case .bloodPressure: return .millimetresOfMercury
        case .bodyWeight: return .kilograms
        case .diopters: return .dioptres
        case .odometer: return .kilometres
        case .engineHours: return .engineHours
        case .cycles: return nil
        case .custom: return nil
        }
    }

    /// Readings that only go up, so a smaller value is a typo or a reset.
    public var isCumulative: Bool {
        switch self {
        case .electricity, .gas, .coldWater, .hotWater, .thermalEnergy, .odometer, .engineHours, .cycles: return true
        case .biomarker, .bloodPressure, .bodyWeight, .diopters, .custom: return false
        }
    }
}

extension DosarSchemaV4 {
    /// A line in a history entry: a part replaced, a job done, a vaccine given.
    /// `componentKey` ties it to the template's component catalog so "when did I
    /// last change the brake pads" has one answer across entries.
    @Model
    public final class ServiceItem {
        public var id: UUID = UUID()
        public var name: String = ""
        /// A key from the template's component catalog, or `custom.<slug>` for free text.
        public var componentKey: String?
        /// Free grouping such as "Frâne" or "Filtre".
        public var group: String?
        public var partBrandOrCode: String?
        public var partSerialNumber: String?
        public var costAmount: Decimal?
        public var laborCostAmount: Decimal?
        public var partsCostAmount: Decimal?
        public var currency: String = Money.defaultCurrency
        /// Who supplied the part, when different from who fitted it.
        public var supplier: Provider?
        /// Batch, lot or RMA number.
        public var batchOrTicket: String?
        /// Position detail such as a tooth number or "Punte spate".
        public var locationDetail: String?
        /// Days the item spent in repair, which extends a legal warranty (OUG 140/2021).
        public var daysInService: Int?
        public var warrantyMonths: Int?
        public var notes: String?
        public var isExample: Bool = false

        public var entry: HistoryEntry?

        @Relationship(deleteRule: .nullify, inverse: \Attachment.serviceItem)
        public var attachments: [Attachment]? = []

        public init(id: UUID = UUID(), name: String, componentKey: String? = nil) {
            self.id = id
            self.name = name
            self.componentKey = componentKey
        }

        /// The total paid: the explicit cost, or labor plus parts.
        public var totalCost: Money? {
            if let costAmount { return Money(costAmount, currency: currency) }
            let sum = (laborCostAmount ?? 0) + (partsCostAmount ?? 0)
            guard laborCostAmount != nil || partsCostAmount != nil else { return nil }
            return Money(sum, currency: currency)
        }
    }

    /// One reading over time: a meter index, a lab value, a weight, an odometer.
    @Model
    public final class MeasurementLog {
        public var id: UUID = UUID()
        public var kindRaw: String = MeasurementKind.custom.rawValue
        /// What was measured, such as "Glicemie" or "Index zi".
        public var name: String = ""
        public var value: Double = 0
        /// Second part of a pair, such as the diastolic pressure.
        public var secondaryValue: Double?
        /// The unit's key (`MeasurementUnit.key`), "" for none. Earlier versions stored its
        /// label ("m³", "kWh"); read and write it through `measurementUnit`.
        public var unit: String = ""
        public var recordedAt: Date = Date()
        public var unitPriceAmount: Decimal?
        public var unitPriceCurrency: String?
        /// Read by the household (true) or estimated by the provider (false).
        public var isSelfRead: Bool = true
        public var referenceMin: Double?
        public var referenceMax: Double?
        /// Lab or provider name.
        public var source: String?
        public var notes: String?
        public var isExample: Bool = false

        public var asset: Asset?

        @Relationship(deleteRule: .nullify, inverse: \Attachment.measurement)
        public var attachments: [Attachment]? = []

        public init(id: UUID = UUID(), kind: MeasurementKind, name: String, value: Double, unit: MeasurementUnit? = nil, recordedAt: Date = Date()) {
            self.id = id
            self.kindRaw = kind.rawValue
            self.name = name
            self.value = value
            self.unit = (unit ?? kind.defaultUnit)?.key ?? ""
            self.recordedAt = recordedAt
        }

        /// The unit, read from any form it was stored in; nil when it has none.
        public var measurementUnit: MeasurementUnit? {
            get { MeasurementUnit(unit) }
            set { unit = newValue?.key ?? "" }
        }

        public var kind: MeasurementKind {
            get { MeasurementKind(rawValue: kindRaw) ?? .custom }
            set { kindRaw = newValue.rawValue }
        }

        public var unitPrice: Money? {
            guard let unitPriceAmount else { return nil }
            return Money(unitPriceAmount, currency: unitPriceCurrency ?? Money.defaultCurrency)
        }

        public var isOutOfRange: Bool {
            if let referenceMin, value < referenceMin { return true }
            if let referenceMax, value > referenceMax { return true }
            return false
        }
    }

    /// A document in the binder: a scanned bill, a policy PDF, a photo of a label.
    ///
    /// It can hold the original file (a PDF or an image), scanned page images
    /// (HEIC) and a thumbnail. It is linked to an asset and optionally to an
    /// obligation, a history entry, a line item, a measurement or a provider.
    /// Documents are never thrown away when replaced: an old policy is archived
    /// and points to the one that superseded it, so it is there for a claim.
    @Model
    public final class Attachment {
        public var id: UUID = UUID()
        /// A short name the person recognizes, such as "Poliță RCA 2026".
        public var title: String?
        public var fileName: String = ""
        public var kindRaw: String = DocumentKind.other.rawValue
        /// Uniform type identifier of the original file, such as `com.adobe.pdf` or `public.jpeg`.
        public var contentType: String = "public.data"
        /// The original file, kept as received.
        @Attribute(.externalStorage) public var fileData: Data?
        /// A small preview image (HEIC or JPEG).
        @Attribute(.externalStorage) public var thumbnailData: Data?
        /// Total bytes of the original and the page images.
        public var byteCount: Int = 0
        /// Lowercase hex SHA-256 of the original, or of the page images in order
        /// when there is no original. Used to spot the same document twice.
        public var sha256: String?
        /// Text read from the document (OCR or PDF text), used by search.
        public var extractedText: String?
        /// The date printed on the document (issue or invoice date), noon of that day.
        public var documentDate: Date?
        /// The last day the document itself is valid, as read when it was filed (a policy's
        /// end), noon of that day. Its deadline moving on later never changes it.
        public var validUntil: Date?
        /// Identifier of the source document in Capture's document store on this
        /// device. Local only: archives don't carry it.
        public var documentID: String?
        /// Kept for reference but no longer current (an old policy).
        public var isArchived: Bool = false
        /// When old page images were re-encoded smaller to save space.
        public var compactedAt: Date?
        public var createdAt: Date = Date()
        public var isExample: Bool = false

        @Relationship(deleteRule: .cascade, inverse: \AttachmentPage.attachment)
        public var pages: [AttachmentPage]? = []

        /// The document that replaced this one.
        public var supersededBy: Attachment?
        @Relationship(deleteRule: .nullify, inverse: \Attachment.supersededBy)
        public var supersedes: [Attachment]? = []

        public var asset: Asset?
        public var obligation: Obligation?
        public var historyEntry: HistoryEntry?
        public var serviceItem: ServiceItem?
        public var measurement: MeasurementLog?
        public var provider: Provider?

        public init(id: UUID = UUID(), fileName: String, contentType: String, data: Data?, kind: DocumentKind = .other) {
            self.id = id
            self.fileName = fileName
            self.contentType = contentType
            self.kindRaw = kind.rawValue
            self.fileData = data
            self.byteCount = data?.count ?? 0
            self.sha256 = data.map(Hashing.sha256)
        }

        public var kind: DocumentKind {
            get { DocumentKind(rawValue: kindRaw) ?? .other }
            set { kindRaw = newValue.rawValue }
        }

        /// Page images in order.
        public var orderedPages: [AttachmentPage] {
            (pages ?? []).sorted { $0.index < $1.index }
        }
    }

    /// One scanned page of a document, stored as HEIC.
    @Model
    public final class AttachmentPage {
        public var id: UUID = UUID()
        /// Zero-based position in the document.
        public var index: Int = 0
        @Attribute(.externalStorage) public var imageData: Data?
        public var attachment: Attachment?

        public init(id: UUID = UUID(), index: Int, imageData: Data?) {
            self.id = id
            self.index = index
            self.imageData = imageData
        }
    }
}

/// What a document is. Raw values are part of the `.dosar` contract.
public enum DocumentKind: String, Codable, CaseIterable, Sendable {
    case invoice
    case receipt
    case policy
    case contract
    case certificate
    case report
    case identity
    case warranty
    case manual
    case prescription
    case photo
    case other
}

/// SHA-256 as lowercase hex, shared by attachments and archives.
public enum Hashing {
    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
