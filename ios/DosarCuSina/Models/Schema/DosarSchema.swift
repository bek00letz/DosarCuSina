import Foundation
import SwiftData

/// The first versioned schema of the household database.
///
/// Every model lives inside this namespace so that a future `DosarSchemaV3` can
/// freeze a copy of these definitions and migrate from them. App code uses the
/// top-level type aliases below and never names the version directly.
///
/// The shapes follow the CloudKit rules from day one: every stored property is
/// optional or has a default, every relationship is optional, and nothing is
/// marked unique. Complex values (field values, template sections, recurrence
/// rules) are stored as JSON `Data` so they stay portable and match the `.dosar`
/// archive encoding exactly.
public enum DosarSchemaV2: VersionedSchema {
    public static let versionIdentifier = Schema.Version(2, 0, 0)

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

/// Migration plan for the household database. There is a single stage-less
/// version today; add a `MigrationStage` here when `DosarSchemaV3` appears.
public enum DosarMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [DosarSchemaV2.self] }
    public static var stages: [MigrationStage] { [] }
}

public typealias CategoryTemplate = DosarSchemaV2.CategoryTemplate
public typealias Asset = DosarSchemaV2.Asset
public typealias Obligation = DosarSchemaV2.Obligation
public typealias HistoryEntry = DosarSchemaV2.HistoryEntry
public typealias ServiceItem = DosarSchemaV2.ServiceItem
public typealias MeasurementLog = DosarSchemaV2.MeasurementLog
public typealias Attachment = DosarSchemaV2.Attachment
public typealias Provider = DosarSchemaV2.Provider
public typealias AttachmentPage = DosarSchemaV2.AttachmentPage

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
