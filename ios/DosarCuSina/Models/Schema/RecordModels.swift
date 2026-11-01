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

    public var defaultUnit: String {
        switch self {
        case .electricity: return "kWh"
        case .gas, .coldWater, .hotWater: return "m³"
        case .thermalEnergy: return "Gcal"
        case .biomarker: return "mg/dL"
        case .bloodPressure: return "mmHg"
        case .bodyWeight: return "kg"
        case .diopters: return "dpt"
        case .odometer: return "km"
        case .engineHours: return "h"
        case .cycles: return ""
        case .custom: return ""
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

extension DosarSchemaV2 {
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

        public init(id: UUID = UUID(), kind: MeasurementKind, name: String, value: Double, unit: String? = nil, recordedAt: Date = Date()) {
            self.id = id
            self.kindRaw = kind.rawValue
            self.name = name
            self.value = value
            self.unit = unit ?? kind.defaultUnit
            self.recordedAt = recordedAt
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

    /// A stored file: a scanned bill, a policy PDF, a photo of a label.
    /// It always belongs to an asset and may also be filed under an obligation,
    /// a history entry, a line item or a measurement.
    @Model
    public final class Attachment {
        public var id: UUID = UUID()
        public var fileName: String = ""
        /// Uniform type identifier, such as `com.adobe.pdf` or `public.jpeg`.
        public var contentType: String = "public.data"
        @Attribute(.externalStorage) public var fileData: Data?
        public var byteCount: Int = 0
        /// Text read from the file (OCR or PDF text), used by search.
        public var extractedText: String?
        public var createdAt: Date = Date()
        public var isExample: Bool = false

        public var asset: Asset?
        public var obligation: Obligation?
        public var historyEntry: HistoryEntry?
        public var serviceItem: ServiceItem?
        public var measurement: MeasurementLog?

        public init(id: UUID = UUID(), fileName: String, contentType: String, data: Data?) {
            self.id = id
            self.fileName = fileName
            self.contentType = contentType
            self.fileData = data
            self.byteCount = data?.count ?? 0
        }
    }
}
