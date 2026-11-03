import Foundation
import SwiftData

/// The current schema of the household database.
///
/// Every model lives inside this namespace so that the next version can freeze a
/// copy of these definitions and migrate from them (as `DosarSchemaV2` to `DosarSchemaV4`
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
/// Version 5 adds whether the person set a deadline's reminders themselves
/// (`Obligation.remindersCustomized`, false by default).
public enum DosarSchemaV5: VersionedSchema {
    public static let versionIdentifier = Schema.Version(5, 0, 0)

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
    public static var schemas: [any VersionedSchema.Type] { [DosarSchemaV2.self, DosarSchemaV3.self, DosarSchemaV4.self, DosarSchemaV5.self] }
    public static var stages: [MigrationStage] { [v2ToV3, v3ToV4, v4ToV5] }

    /// Version 3 only adds optional attributes; existing records keep every value. What
    /// the new attributes should hold for old records is filled in later: the categories'
    /// behaviour when the built-ins are upgraded at launch, the rest by the repair list.
    static var v2ToV3: MigrationStage { .lightweight(fromVersion: DosarSchemaV2.self, toVersion: DosarSchemaV3.self) }

    /// Version 4 only adds a number with a default (no travel margin); existing deadlines
    /// keep every value. A passport deadline gets its margin from the repair list, with the
    /// owner's OK, because it changes when it reminds.
    static var v3ToV4: MigrationStage { .lightweight(fromVersion: DosarSchemaV3.self, toVersion: DosarSchemaV4.self) }

    /// Version 5 only adds a flag with a default (the reminders are the deadline's own);
    /// existing deadlines keep every value. A deadline whose reminders the person changed
    /// before version 5 isn't known as changed: its reminders still follow its document
    /// when the document's type changes, which is what the type change asks for.
    static var v4ToV5: MigrationStage { .lightweight(fromVersion: DosarSchemaV4.self, toVersion: DosarSchemaV5.self) }
}

public typealias CategoryTemplate = DosarSchemaV5.CategoryTemplate
public typealias Asset = DosarSchemaV5.Asset
public typealias Obligation = DosarSchemaV5.Obligation
public typealias HistoryEntry = DosarSchemaV5.HistoryEntry
public typealias ServiceItem = DosarSchemaV5.ServiceItem
public typealias MeasurementLog = DosarSchemaV5.MeasurementLog
public typealias Attachment = DosarSchemaV5.Attachment
public typealias Provider = DosarSchemaV5.Provider
public typealias AttachmentPage = DosarSchemaV5.AttachmentPage

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
