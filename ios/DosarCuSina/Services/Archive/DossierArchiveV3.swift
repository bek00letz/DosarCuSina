import Foundation

/// The `.dosar` v3 records, field for field as `shared/schemas/dosar-v3.md`
/// describes them. Identifiers are lowercase UUID strings, timestamps are
/// ISO 8601 UTC, calendar days are `yyyy-MM-dd`, money is a decimal string
/// with a currency code. Optional values are omitted when empty.
public enum DossierV3 {
    public static let format = "com.ar.dosarcusina.dossier"
    public static let schemaVersion = 3

    public enum Path {
        public static let manifest = "manifest.json"
        public static let templates = "data/templates.json"
        public static let assets = "data/assets.json"
        public static let obligations = "data/obligations.json"
        public static let history = "data/history.json"
        public static let serviceItems = "data/service_items.json"
        public static let providers = "data/providers.json"
        public static let measurements = "data/measurements.json"
        public static let attachments = "data/attachments.json"
        public static let vaultPrefix = "vault/"
        public static let photosPrefix = "vault/photos/"
        public static let opis = "opis.pdf"

        public static let dataFiles = [templates, assets, obligations, history, serviceItems, providers, measurements, attachments]
    }

    public struct Manifest: Codable, Hashable, Sendable {
        public var format: String
        public var schemaVersion: Int
        public var appVersion: String
        public var platform: String
        public var exportedAt: Date
        public var counts: Counts
        /// SHA-256 (lowercase hex) of every other file in the archive, by path.
        public var checksums: [String: String]

        public struct Counts: Codable, Hashable, Sendable {
            public var templates: Int
            public var assets: Int
            public var obligations: Int
            public var historyEntries: Int
            public var serviceItems: Int
            public var providers: Int
            public var measurements: Int
            public var attachments: Int
        }
    }

    public struct Template: Codable, Hashable, Sendable {
        public var key: String
        public var name: String
        public var summary: String?
        public var symbol: String
        public var tint: String
        public var heroStyle: String
        public var isBuiltIn: Bool
        public var version: Int
        public var homeOrder: Int
        public var isOnHome: Bool
        public var isSensitive: Bool
        public var sections: [FieldSection]
        public var blueprints: [ObligationBlueprint]
        public var components: [ComponentDefinition]?
        public var createdAt: Date
        public var updatedAt: Date
    }

    public struct Asset: Codable, Hashable, Sendable {
        public var id: String
        public var templateKey: String
        public var name: String
        public var symbolOverride: String?
        public var tintOverride: String?
        public var notes: String?
        public var values: FieldValues
        /// `vault/photos/<id>.jpg` when the asset has a photo.
        public var photoPath: String?
        public var isExample: Bool
        public var createdAt: Date
        public var updatedAt: Date
    }

    public struct Obligation: Codable, Hashable, Sendable {
        public var id: String
        public var assetId: String?
        public var title: String
        public var notes: String?
        public var blueprintKey: String?
        public var kind: String
        public var dueDate: CalendarDay
        public var dueMetric: Double?
        public var reminders: ReminderProfile
        public var reminderMinuteOfDay: Int?
        public var recurrence: RecurrenceRule
        public var estimatedCost: Money?
        public var provider: String?
        public var reference: String?
        public var status: String
        public var snoozedUntil: Date?
        public var isExample: Bool
        public var createdAt: Date
        public var updatedAt: Date
    }

    public struct HistoryEntry: Codable, Hashable, Sendable {
        public var id: String
        public var assetId: String?
        public var obligationId: String?
        public var kind: String
        public var title: String
        public var occurredAt: Date
        public var metricReading: Double?
        public var totalCost: Money?
        public var note: String?
        public var rating: Int?
        /// Set when the entry completed an obligation.
        public var cycleDueDate: CalendarDay?
        public var nextDueDate: CalendarDay?
        public var previousStatus: String?
        public var previousDueMetric: Double?
        public var providerIds: [String]
        public var isExample: Bool
    }

    public struct ServiceItem: Codable, Hashable, Sendable {
        public var id: String
        public var entryId: String?
        public var componentKey: String?
        public var name: String
        public var group: String?
        public var partBrandOrCode: String?
        public var partSerialNumber: String?
        public var cost: Money?
        public var laborCost: Money?
        public var partsCost: Money?
        public var supplierId: String?
        public var batchOrTicket: String?
        public var locationDetail: String?
        public var daysInService: Int?
        public var warrantyMonths: Int?
        public var notes: String?
        public var isExample: Bool
    }

    public struct Provider: Codable, Hashable, Sendable {
        public var id: String
        public var name: String
        public var trades: [String]
        public var phone: String?
        public var email: String?
        public var address: String?
        public var notes: String?
        public var manualRating: Int?
        public var wouldCallAgain: Bool?
        public var assetIds: [String]
        public var isExample: Bool
        public var createdAt: Date
        public var updatedAt: Date
    }

    public struct Measurement: Codable, Hashable, Sendable {
        public var id: String
        public var assetId: String?
        public var kind: String
        public var name: String
        public var value: Double
        public var secondaryValue: Double?
        public var unit: String
        public var recordedAt: Date
        public var unitPrice: Money?
        public var isSelfRead: Bool
        public var referenceMin: Double?
        public var referenceMax: Double?
        public var source: String?
        public var notes: String?
        public var isExample: Bool
    }

    public struct Attachment: Codable, Hashable, Sendable {
        public var id: String
        public var title: String?
        public var fileName: String
        public var kind: String
        /// Type of the original file.
        public var contentType: String
        public var byteCount: Int
        public var sha256: String?
        /// The original file, `vault/<id>.<ext>`, when there is one.
        public var path: String?
        /// Scanned pages, `vault/<id>/page-<n>.heic`, in order.
        public var pagePaths: [String]
        /// `vault/<id>/thumbnail.<ext>`.
        public var thumbnailPath: String?
        public var extractedText: String?
        public var documentDate: CalendarDay?
        public var isArchived: Bool
        public var supersededById: String?
        public var createdAt: Date
        public var isExample: Bool
        public var assetId: String?
        public var obligationId: String?
        public var historyEntryId: String?
        public var serviceItemId: String?
        public var measurementId: String?
        public var providerId: String?

        /// Every file this record points to.
        public var allPaths: [String] { [path, thumbnailPath].compactMap { $0 } + pagePaths }
    }

    /// Everything an archive holds, decoded and checked.
    public struct Package: Sendable {
        public var manifest: Manifest
        public var templates: [Template]
        public var assets: [Asset]
        public var obligations: [Obligation]
        public var historyEntries: [HistoryEntry]
        public var serviceItems: [ServiceItem]
        public var providers: [Provider]
        public var measurements: [Measurement]
        public var attachments: [Attachment]
        /// File contents by archive path (`vault/…`).
        public var files: [String: Data]
    }

    // MARK: Coding

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(Date.ISO8601FormatStyle()))
        }
        return encoder
    }

    /// Accepts timestamps with or without fractional seconds and with any UTC offset.
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = parseTimestamp(raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 timestamp: \(raw)")
        }
        return decoder
    }

    static func parseTimestamp(_ raw: String) -> Date? {
        if let date = try? Date(raw, strategy: .iso8601) { return date }
        if let date = try? Date(raw, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
        if let day = CalendarDay(isoString: raw), raw.count == 10 {
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
            return day.startDate(in: utc)
        }
        return nil
    }

    static func id(_ uuid: UUID) -> String { uuid.uuidString.lowercased() }
    static func id(_ uuid: UUID?) -> String? { uuid.map(id) }
}
