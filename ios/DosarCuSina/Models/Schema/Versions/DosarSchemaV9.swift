import Foundation
import SwiftData

/// The household database as version 9 shipped, frozen so a store written by it can be
/// opened and migrated (`DosarMigrationPlan`). Only what is stored is kept here: the
/// attributes and relationships exactly as they were, with no behaviour. Version 9 is
/// version 8 with every day kept as a day (`StoredDay`): a deadline's due day and the day its
/// snooze ends, a completion's due days, a document's date and its last valid day. A
/// deadline doesn't keep since when its cycle is known, which version 10 adds.
///
/// Never change this file. `SchemaMigrationTests` compares it with the shape version 9
/// stores have on people's phones.
public enum DosarSchemaV9: VersionedSchema {
    public static let versionIdentifier = Schema.Version(9, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            CategoryTemplate.self,
            Asset.self,
            Obligation.self,
            HistoryEntry.self,
            ServiceItem.self,
            MeasurementLog.self,
            Attachment.self,
            AttachmentPage.self,
            Provider.self,
        ]
    }

    @Model
    public final class CategoryTemplate {
        public var key: String = ""
        public var name: String = ""
        public var summary: String?
        public var symbol: String = "square.grid.2x2"
        public var tintRaw: String = "gray"
        public var heroStyleRaw: String = "standard"
        public var isBuiltIn: Bool = false
        public var builtInVersion: Int = 0
        public var homeOrder: Int = 0
        public var isOnHome: Bool = true
        public var isSensitive: Bool = false
        public var sectionsData: Data?
        public var blueprintsData: Data?
        public var componentsData: Data?
        public var pocketsRaw: [String] = []
        public var behaviorData: Data?
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()

        public init(key: String) { self.key = key }
    }

    @Model
    public final class Asset {
        public var id: UUID = UUID()
        public var name: String = ""
        public var templateKey: String = ""
        public var symbolOverride: String?
        public var tintOverrideRaw: String?
        public var notes: String?
        @Attribute(.externalStorage) public var photoData: Data?
        public var valuesData: Data?
        public var customFactsData: Data?
        public var isExample: Bool = false
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()

        @Relationship(deleteRule: .cascade, inverse: \Obligation.asset)
        public var obligations: [Obligation]? = []
        @Relationship(deleteRule: .cascade, inverse: \Attachment.asset)
        public var attachments: [Attachment]? = []
        @Relationship(deleteRule: .cascade, inverse: \HistoryEntry.asset)
        public var history: [HistoryEntry]? = []
        @Relationship(deleteRule: .cascade, inverse: \MeasurementLog.asset)
        public var measurements: [MeasurementLog]? = []
        public var providers: [Provider]? = []
        public var parent: Asset?
        @Relationship(deleteRule: .nullify, inverse: \Asset.parent)
        public var children: [Asset]? = []

        public init(name: String, templateKey: String) {
            self.name = name
            self.templateKey = templateKey
        }
    }

    @Model
    public final class Obligation {
        public var id: UUID = UUID()
        public var title: String = ""
        public var notes: String?
        public var blueprintKey: String?
        public var kindRaw: String = "routine"
        public var dueDayISO: String = ""
        public var dueMetric: Double?
        public var reminderLeadDays: [Int] = [30, 7, 0]
        public var consequenceRaw: String = "comfort"
        public var graceDays: Int = 0
        public var followUpAfterLapse: Bool = false
        public var travelMarginDays: Int = 0
        public var remindersCustomized: Bool = false
        public var reminderMinuteOfDay: Int?
        public var recurrenceData: Data?
        public var estimatedCostAmount: Decimal?
        public var estimatedCostCurrency: String?
        public var provider: String?
        public var reference: String?
        public var statusRaw: String = "active"
        public var snoozedUntilISO: String?
        public var isExample: Bool = false
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()

        public var asset: Asset?
        @Relationship(deleteRule: .nullify, inverse: \HistoryEntry.obligation)
        public var historyEntries: [HistoryEntry]? = []
        @Relationship(deleteRule: .nullify, inverse: \Attachment.obligation)
        public var attachments: [Attachment]? = []

        public init(title: String) { self.title = title }
    }

    @Model
    public final class HistoryEntry {
        public var id: UUID = UUID()
        public var kindRaw: String = "note"
        public var title: String = ""
        public var occurredAt: Date = Date()
        public var metricReading: Double?
        public var totalCostAmount: Decimal?
        public var totalCostCurrency: String?
        public var note: String?
        public var reference: String?
        public var rating: Int?
        public var isExample: Bool = false
        public var cycleDueDayISO: String?
        public var nextDueDayISO: String?
        public var previousStatusRaw: String?
        public var previousDueMetric: Double?
        public var updatedAt: Date = Date.distantPast

        public var asset: Asset?
        public var obligation: Obligation?
        public var providers: [Provider]? = []
        @Relationship(deleteRule: .cascade, inverse: \ServiceItem.entry)
        public var items: [ServiceItem]? = []
        @Relationship(deleteRule: .nullify, inverse: \Attachment.historyEntry)
        public var attachments: [Attachment]? = []

        public init(title: String) { self.title = title }
    }

    @Model
    public final class ServiceItem {
        public var id: UUID = UUID()
        public var name: String = ""
        public var componentKey: String?
        public var group: String?
        public var partBrandOrCode: String?
        public var partSerialNumber: String?
        public var costAmount: Decimal?
        public var laborCostAmount: Decimal?
        public var partsCostAmount: Decimal?
        public var currency: String = "RON"
        public var supplier: Provider?
        public var batchOrTicket: String?
        public var locationDetail: String?
        public var daysInService: Int?
        public var warrantyMonths: Int?
        public var notes: String?
        public var isExample: Bool = false
        public var updatedAt: Date = Date.distantPast

        public var entry: HistoryEntry?
        @Relationship(deleteRule: .nullify, inverse: \Attachment.serviceItem)
        public var attachments: [Attachment]? = []

        public init(name: String) { self.name = name }
    }

    @Model
    public final class MeasurementLog {
        public var id: UUID = UUID()
        public var kindRaw: String = "custom"
        public var name: String = ""
        public var value: Double = 0
        public var secondaryValue: Double?
        public var unit: String = ""
        public var recordedAt: Date = Date()
        public var unitPriceAmount: Decimal?
        public var unitPriceCurrency: String?
        public var isSelfRead: Bool = true
        public var referenceMin: Double?
        public var referenceMax: Double?
        public var source: String?
        public var notes: String?
        public var isExample: Bool = false
        public var updatedAt: Date = Date.distantPast

        public var asset: Asset?
        @Relationship(deleteRule: .nullify, inverse: \Attachment.measurement)
        public var attachments: [Attachment]? = []

        public init(name: String, value: Double) {
            self.name = name
            self.value = value
        }
    }

    @Model
    public final class Attachment {
        public var id: UUID = UUID()
        public var title: String?
        public var fileName: String = ""
        public var kindRaw: String = "other"
        public var contentType: String = "public.data"
        @Attribute(.externalStorage) public var fileData: Data?
        @Attribute(.externalStorage) public var thumbnailData: Data?
        public var byteCount: Int = 0
        public var sha256: String?
        public var extractedText: String?
        public var documentDayISO: String?
        public var validUntilISO: String?
        public var documentID: String?
        public var isArchived: Bool = false
        public var compactedAt: Date?
        public var framingData: Data?
        public var createdAt: Date = Date()
        public var isExample: Bool = false
        public var updatedAt: Date = Date.distantPast

        @Relationship(deleteRule: .cascade, inverse: \AttachmentPage.attachment)
        public var pages: [AttachmentPage]? = []
        public var supersededBy: Attachment?
        @Relationship(deleteRule: .nullify, inverse: \Attachment.supersededBy)
        public var supersedes: [Attachment]? = []
        public var asset: Asset?
        public var obligation: Obligation?
        public var historyEntry: HistoryEntry?
        public var serviceItem: ServiceItem?
        public var measurement: MeasurementLog?
        public var provider: Provider?

        public init(fileName: String) { self.fileName = fileName }
    }

    @Model
    public final class AttachmentPage {
        public var id: UUID = UUID()
        public var index: Int = 0
        @Attribute(.externalStorage) public var imageData: Data?
        public var attachment: Attachment?

        public init(index: Int) { self.index = index }
    }

    @Model
    public final class Provider {
        public var id: UUID = UUID()
        public var name: String = ""
        public var trades: [String] = []
        public var phone: String?
        public var email: String?
        public var address: String?
        public var notes: String?
        public var manualRating: Int?
        public var wouldCallAgain: Bool?
        public var contactIdentifier: String?
        public var taxID: String?
        public var isExample: Bool = false
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()

        @Relationship(deleteRule: .nullify, inverse: \Asset.providers)
        public var assets: [Asset]? = []
        @Relationship(deleteRule: .nullify, inverse: \HistoryEntry.providers)
        public var historyEntries: [HistoryEntry]? = []
        @Relationship(deleteRule: .nullify, inverse: \ServiceItem.supplier)
        public var suppliedItems: [ServiceItem]? = []
        @Relationship(deleteRule: .nullify, inverse: \Attachment.provider)
        public var attachments: [Attachment]? = []

        public init(name: String) { self.name = name }
    }
}
