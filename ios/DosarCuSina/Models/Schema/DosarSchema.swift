import Foundation
import SwiftData

/// The current schema of the household database.
///
/// Every model lives inside this namespace so that the next version can freeze a
/// copy of these definitions and migrate from them (as `DosarSchemaV2` and `DosarSchemaV3`
/// are frozen in `Versions/`). App code uses the top-level type aliases below and never names the
/// version directly.
///
/// The shapes follow the CloudKit rules from day one: every stored property is
/// optional or has a default, every relationship is optional, and nothing is
/// marked unique. Complex values (field values, template sections, recurrence
/// rules) are stored as JSON `Data` so they stay portable and match the `.dosar`
/// archive encoding exactly.
///
/// Version 3 added, all optional: a firm's tax ID (`Provider.taxID`), what a category
/// does (`CategoryTemplate.behaviorData`) and the last day a filed document is valid
/// (`Attachment.validUntil`). Version 4 adds how long before its due day a deadline's
/// document stops being good for travel (`Obligation.travelMarginDays`, 0 by default).
public enum DosarSchemaV4: VersionedSchema {
    public static let versionIdentifier = Schema.Version(4, 0, 0)

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
}

/// Migration plan for the household database, oldest version first. Every new
/// version freezes the one before it in `Versions/`, adds a stage here, and gets a
/// test that opens a store written by the version before (`SchemaMigrationTests`).
public enum DosarMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [DosarSchemaV2.self, DosarSchemaV3.self, DosarSchemaV4.self] }
    public static var stages: [MigrationStage] { [v2ToV3, v3ToV4] }

    /// Version 3 only adds optional attributes; existing records keep every value. What
    /// the new attributes should hold for old records is filled in later: the categories'
    /// behaviour when the built-ins are upgraded at launch, the rest by the repair list.
    static var v2ToV3: MigrationStage { .lightweight(fromVersion: DosarSchemaV2.self, toVersion: DosarSchemaV3.self) }

    /// Version 4 only adds a number with a default (no travel margin); existing deadlines
    /// keep every value. A passport deadline gets its margin from the repair list, with the
    /// owner's OK, because it changes when it reminds.
    static var v3ToV4: MigrationStage { .lightweight(fromVersion: DosarSchemaV3.self, toVersion: DosarSchemaV4.self) }
}

public typealias CategoryTemplate = DosarSchemaV4.CategoryTemplate
public typealias Asset = DosarSchemaV4.Asset
public typealias Obligation = DosarSchemaV4.Obligation
public typealias HistoryEntry = DosarSchemaV4.HistoryEntry
public typealias ServiceItem = DosarSchemaV4.ServiceItem
public typealias MeasurementLog = DosarSchemaV4.MeasurementLog
public typealias Attachment = DosarSchemaV4.Attachment
public typealias Provider = DosarSchemaV4.Provider
public typealias AttachmentPage = DosarSchemaV4.AttachmentPage

/// Shared JSON coding for values stored as `Data` on models and written to archives.
/// Keys are sorted so the same value always produces the same bytes.
enum StoredJSON {
    static func encode<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
