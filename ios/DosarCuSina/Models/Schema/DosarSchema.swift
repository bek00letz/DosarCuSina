import Foundation
import SwiftData

/// The current schema of the household database.
///
/// Every model lives inside this namespace so that the next version can freeze a
/// copy of these definitions and migrate from them (as `DosarSchemaV2` to `DosarSchemaV12`
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
/// (`Obligation.remindersCustomized`, false by default). Version 6 adds how a document's
/// pages are shown: the document found in each photo and which way up it goes
/// (`Attachment.framingData`, none by default). Version 7 adds the number of the paper a
/// history entry records (`HistoryEntry.reference`: a bill's invoice number), so a bill is
/// known by it when it is filed again from another photo (`PaperIdentity`). Version 8 adds
/// when a history entry, a line item, a reading and a document last changed (`updatedAt`,
/// as sections, deadlines, firms and categories already had), so a backup brought in with
/// "Adaugă" keeps the newer copy of every record by one rule (`ArchiveMerge`). Version 9
/// keeps every day as a day (`StoredDay`): a deadline's due day and the day its snooze ends, the
/// due days a completion closed and moved to, a document's date and its last valid day were
/// moments before (noon, or the start of the day, in the phone's time zone), which read as
/// another day on a phone ten or more hours away. Version 10 adds whether a reading starts a
/// new counter (`MeasurementLog.startsCounter`, false by default): a replaced meter or
/// dashboard, or one that went round past its last digit, counts on from there on its own.
/// Version 11 adds since when a deadline's cycle is known as it now is
/// (`Obligation.cycleKnownAt`: its due day, its reminders' leads and whether it is active,
/// whoever changed them; none by default, which reads as its change time), so a reminder that
/// makes up for warnings already passed counts from then. Version 12 adds what a newer build wrote
/// in a deadline's reminders that this one doesn't read (`Obligation.remindersData`, the profile's
/// JSON, none by default), so a backup from a newer build keeps it through this one, and keeps a
/// category's lock on each device instead (`SectionLocks`), never in the store. Version 13 adds
/// which copy of a record this is (`copyID` on every model, none by default), given by the device
/// that made the copy: the same binder on two devices has the same ids, so iCloud brings two copies
/// of each record, and every device joins them into the same one by it (`RecordsMeet`).
public enum DosarSchemaV13: VersionedSchema {
    public static let versionIdentifier = Schema.Version(13, 0, 0)

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
    public static var schemas: [any VersionedSchema.Type] { [DosarSchemaV2.self, DosarSchemaV3.self, DosarSchemaV4.self, DosarSchemaV5.self, DosarSchemaV6.self, DosarSchemaV7.self, DosarSchemaV8.self, DosarSchemaV9.self, DosarSchemaV10.self, DosarSchemaV11.self, DosarSchemaV12.self, DosarSchemaV13.self] }
    public static var stages: [MigrationStage] { [v2ToV3, v3ToV4, v4ToV5, v5ToV6, v6ToV7, v7ToV8, v8ToV9, v9ToV10, v10ToV11, v11ToV12, v12ToV13] }

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

    /// Version 6 only adds an optional value (how a document's pages are shown); existing
    /// documents keep every value and show their pages as before, whole and as taken. Only
    /// documents captured from then on are cut out of their photo and turned upright.
    static var v5ToV6: MigrationStage { .lightweight(fromVersion: DosarSchemaV5.self, toVersion: DosarSchemaV6.self) }

    /// Version 7 only adds an optional value (the number of the paper a history entry
    /// records); existing entries keep every value. A bill filed before kept its number only
    /// in its note ("Factura nr. …"); the repair list moves it to its place
    /// (`BillNumbersStep`), and asks before joining a bill logged twice (`SameBillTwiceStep`).
    static var v6ToV7: MigrationStage { .lightweight(fromVersion: DosarSchemaV6.self, toVersion: DosarSchemaV7.self) }

    /// Version 8 only adds a change time with a default to history entries, line items,
    /// readings and documents; existing records keep every value. When they last changed
    /// isn't known, so they take `ChangeTime.unknown`, the oldest moment: the same on every
    /// phone, so the same record from two phones is never taken for a newer one, and any
    /// change made from now on is newer than it.
    static var v7ToV8: MigrationStage { .lightweight(fromVersion: DosarSchemaV7.self, toVersion: DosarSchemaV8.self) }

    /// Version 9 keeps every day as a day (`StoredDay`) instead of a moment. Before the store
    /// changes shape, each moment is read as the day it meant in the phone's time zone at that
    /// moment (`DayMigration`); after, the days are written into their new places and saved once.
    /// Nothing else changes, change times included.
    static var v8ToV9: MigrationStage { DayMigration.stage }

    /// Version 10 only adds a flag with a default (a reading doesn't start a new counter);
    /// existing readings keep every value and make one series per section and unit, as
    /// before. Nothing guesses where an old meter was replaced: the next lower reading asks,
    /// and the person can answer "Contor nou".
    static var v9ToV10: MigrationStage { .lightweight(fromVersion: DosarSchemaV9.self, toVersion: DosarSchemaV10.self) }

    /// Version 11 only adds an optional moment (since when a deadline's cycle is known as it
    /// now is); existing deadlines keep every value. None is known yet, so each reads its
    /// change time (`Obligation.cycleKnownSince`), what reminders counted from before; the
    /// next change to its due day, its leads or whether it is active, by the person or the
    /// app, gives it its own.
    static var v10ToV11: MigrationStage { .lightweight(fromVersion: DosarSchemaV10.self, toVersion: DosarSchemaV11.self) }

    /// Version 12 adds an optional value (what a newer build wrote in a deadline's reminders that
    /// this one doesn't read; existing deadlines have none, which is what they hold) and takes a
    /// category's lock out of the store, where iCloud would carry it: each device keeps its own
    /// (`SectionLocks`). Before the store changes shape, every category's lock becomes this
    /// device's choice, so every lock stays as it was.
    static var v11ToV12: MigrationStage {
        .custom(fromVersion: DosarSchemaV11.self, toVersion: DosarSchemaV12.self, willMigrate: { context in
            let locks = try context.fetch(FetchDescriptor<DosarSchemaV11.CategoryTemplate>())
                .reduce(into: [String: Bool]()) { locks, template in locks[template.key] = (locks[template.key] ?? false) || template.isSensitive }
            SectionLocks.of(context.container).adopt(locks)
        }, didMigrate: nil)
    }

    /// Version 13 only adds an optional value to every model (which copy of the record this is);
    /// existing records keep every value and have none. Nothing guesses one for them here: two
    /// devices would guess differently for the same record. The device that made a copy gives it
    /// one when it meets another copy of the same record (`RecordsMeet`), and every record made
    /// from now on has one from the start.
    static var v12ToV13: MigrationStage { .lightweight(fromVersion: DosarSchemaV12.self, toVersion: DosarSchemaV13.self) }
}

public typealias CategoryTemplate = DosarSchemaV13.CategoryTemplate
public typealias Asset = DosarSchemaV13.Asset
public typealias Obligation = DosarSchemaV13.Obligation
public typealias HistoryEntry = DosarSchemaV13.HistoryEntry
public typealias ServiceItem = DosarSchemaV13.ServiceItem
public typealias MeasurementLog = DosarSchemaV13.MeasurementLog
public typealias Attachment = DosarSchemaV13.Attachment
public typealias Provider = DosarSchemaV13.Provider
public typealias AttachmentPage = DosarSchemaV13.AttachmentPage

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
