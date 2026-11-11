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
        /// Whether the device that made the backup kept the category locked (`SectionLocks`): bringing
        /// it in may lock the category on this device, never open it.
        public var isSensitive: Bool
        /// Entries this build can't read (from a newer one) are kept raw, in their places.
        public var sections: KeptList<FieldSection>
        public var blueprints: KeptList<ObligationBlueprint>
        public var components: KeptList<ComponentDefinition>?
        /// `SectionPocket` raw values; missing means the standard set.
        public var pockets: [String]?
        public var createdAt: Date
        public var updatedAt: Date
        /// What the category does (its box, its list, its part); missing means the standard behaviour.
        /// Like a section's values, a deadline's recurrence and a document's framing, what a newer
        /// build wrote inside it that this one doesn't read comes in and goes out as written (`KeptObject`).
        public var behavior: KeptObject<CategoryBehavior>?
    }

    public struct Asset: Codable, Hashable, Sendable {
        public var id: String
        public var templateKey: String
        public var name: String
        /// The asset this one is filed under.
        public var parentId: String?
        public var symbolOverride: String?
        public var tintOverride: String?
        public var notes: String?
        public var values: KeptObject<FieldValues>
        /// Free label–value rows under Date importante; rows this build can't read are kept raw.
        public var customFacts: KeptList<CustomFact>?
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
        /// As stored: what a newer build wrote in it that this one doesn't read comes in and goes out
        /// as written (`Obligation.keptReminders`).
        public var reminders: KeptObject<ReminderProfile>
        public var reminderMinuteOfDay: Int?
        public var recurrence: KeptObject<RecurrenceRule>
        public var estimatedCost: Money?
        public var provider: String?
        public var reference: String?
        public var status: String
        public var snoozedUntil: Date?
        public var isExample: Bool
        public var createdAt: Date
        public var updatedAt: Date
        /// The person set the reminders themselves; written only when true, missing reads as false.
        public var remindersCustomized: Bool? = nil
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
        /// The number of the paper the entry records (a bill's invoice number); missing when none.
        public var reference: String? = nil
        /// When it last changed; missing in archives from before version 8 of the database, which reads as `ChangeTime.unknown`.
        public var updatedAt: Date? = nil
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
        /// When it last changed; missing in archives from before version 8 of the database, which reads as `ChangeTime.unknown`.
        public var updatedAt: Date? = nil
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
        /// The firm's tax ID (CUI), digits only.
        public var taxID: String?
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
        /// When it last changed; missing in archives from before version 8 of the database, which reads as `ChangeTime.unknown`.
        public var updatedAt: Date? = nil
        /// True on the first reading of a new counter ("Contor nou"); written only then, and
        /// missing in archives from before version 10 of the database, which read as one counter.
        public var startsCounter: Bool? = nil
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
        /// The last day the document itself is valid, as read when it was filed.
        public var validUntil: CalendarDay?
        /// How the pages are shown: the document found in each photo and which way up it
        /// goes. Absent when every page is shown as it is.
        public var framing: KeptObject<DocumentFraming>? = nil
        /// When it last changed; missing in archives from before version 8 of the database, which reads as `ChangeTime.unknown`.
        public var updatedAt: Date? = nil

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
        /// The documents' and photos' files by archive path (`vault/…`), each read only when
        /// it is written into the database.
        public var files: ArchiveFiles
    }

    /// An archive's files by path, kept where the reader put them (a folder of their own on
    /// disk), so a package holds none of them in memory. The importer reads each one as it
    /// writes the record it belongs to.
    public struct ArchiveFiles: Sendable, ExpressibleByDictionaryLiteral {
        enum Content: Sendable {
            /// Read already: a small package made by hand (tests).
            case data(Data)
            /// Taken out of the archive into a file of its own.
            case file(URL)
            /// Checked against its checksum, not kept: what a summary read leaves.
            case checked
        }

        private var contents: [String: Content]

        init(_ contents: [String: Content] = [:]) {
            self.contents = contents
        }

        public init(dictionaryLiteral elements: (String, Data)...) {
            contents = Dictionary(elements.map { ($0.0, Content.data($0.1)) }, uniquingKeysWith: { _, last in last })
        }

        /// Every path, sorted.
        public var paths: [String] { contents.keys.sorted() }

        public var isEmpty: Bool { contents.isEmpty }

        public func contains(_ path: String) -> Bool { contents[path] != nil }

        /// The file's bytes, or nil when the archive has no such file. A file taken out to
        /// disk is mapped rather than copied where the system allows, so a context holding it
        /// until it saves holds no copy of it.
        public func data(at path: String) throws -> Data? {
            switch contents[path] {
            case .data(let data): return data
            case .file(let url): return try Data(contentsOf: url, options: .mappedIfSafe)
            case .checked: throw ArchiveError.missingFile(path)
            case nil: return nil
            }
        }
    }

    // MARK: Coding

    /// The archive's JSON: indented, keys sorted, moments in UTC to the second
    /// (`MachineText.jsonEncoder(.readable)`).
    public static func encoder() -> JSONEncoder {
        MachineText.jsonEncoder(.readable)
    }

    /// Accepts timestamps with or without fractional seconds, with any UTC offset, or a
    /// day alone (`MachineText.jsonDecoder`).
    public static func decoder() -> JSONDecoder {
        MachineText.jsonDecoder()
    }

    static func id(_ uuid: UUID) -> String { uuid.uuidString.lowercased() }

    /// A record's change time as written: none when it isn't known (`ChangeTime.unknown`),
    /// which is how a reader takes a missing one.
    static func changeTime(_ date: Date) -> Date? { date == ChangeTime.unknown ? nil : date }

    /// Stored properties a backup never carries, by record type, each for a reason; every
    /// other stored property travels (`ArchiveRoundTripTests` checks it against the models).
    /// - `Attachment.documentID`: the document's place in capture's store on this phone.
    /// - `Attachment.compactedAt`: when this phone made its pages smaller.
    /// - `Provider.contactIdentifier`: the card in this phone's Contacts.
    /// - `AttachmentPage.id`: a page is known by its document and its place in it.
    /// - `Obligation.cycleKnownAt`: since when this phone's reminders count the deadline's cycle;
    ///   a copy a backup brings reads as known since its change time (`cycleKnownSince`).
    /// - `copyID`, on every record: which copy of the record this is, given by the device that
    ///   made the copy. A record a backup brings in is a new copy, with one of its own; carried
    ///   along, two devices' copies would look like one and could never be told apart
    ///   (`RecordsMeet`).
    static let stayOnThePhone: [String: Set<String>] = [
        "Asset": ["copyID"],
        "Obligation": ["cycleKnownAt", "copyID"],
        "HistoryEntry": ["copyID"],
        "ServiceItem": ["copyID"],
        "MeasurementLog": ["copyID"],
        "Attachment": ["documentID", "compactedAt", "copyID"],
        "Provider": ["contactIdentifier", "copyID"],
        "AttachmentPage": ["id", "copyID"],
        "CategoryTemplate": ["copyID"],
    ]
    static func id(_ uuid: UUID?) -> String? { uuid.map(id) }
}
