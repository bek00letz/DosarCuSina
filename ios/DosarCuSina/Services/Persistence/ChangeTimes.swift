import Foundation
import SwiftData

/// When a record last changed: the one value a backup brought in with "Adaugă" compares to
/// keep the newer copy of a record that is on both sides (`ArchiveMerge`).
public enum ChangeTime {
    /// The change time of a record from before it was kept (a history entry, a line item, a
    /// reading or a document saved before version 8, or one from a backup that carries none):
    /// older than any change, and the same on every phone, so two copies of a record nobody
    /// has changed since are never taken for a newer one. Equal to the default the schema
    /// gives those records (`DosarSchemaV8`).
    public static let unknown = Date.distantPast
}

/// A record that keeps when it last changed (`updatedAt`): sections, deadlines, firms,
/// categories, history entries, line items, readings and documents.
public protocol ChangeTimed: UndoableRecord {
    var updatedAt: Date { get set }
}

/// A record that is part of another and keeps no change time of its own: changing it is a
/// change to the record it belongs to (a document's page is a change to the document).
protocol PartOfChangeTimed: UndoableRecord {
    /// The stored relationship to the record it belongs to.
    static var wholeProperty: String { get }
}

/// The one rule for change times, kept by `UnitOfWork` as it saves: a record whose own
/// values or links changed gets a new change time, unless the step gave it one itself
/// (`AssetActions` passing its own clock). A step that leaves the time as it was, even by
/// writing the same time again, is taken as giving none. A record only linked to (a section that got a
/// new visit) hasn't changed: the visit keeps the link. Records a step creates have the
/// time they were made. Undo puts change times back with everything else, so a step taken
/// back is as if it never happened.
///
/// A backup's own writer (`UnitOfWork.performPrivate`) keeps the times the backup carries.
enum ChangeTimes {
    /// Gives a new change time, `now`, to every record `context` is about to save whose own
    /// values or links changed, and to the record each changed part belongs to.
    static func stamp(_ context: ModelContext, now: Date = Date()) {
        context.processPendingChanges()
        let changed = context.changedModelsArray
        let parts = changed + context.insertedModelsArray + context.deletedModelsArray
        guard !changed.isEmpty || !parts.isEmpty else { return }
        // The store still holds every record as it was before these changes.
        let store = ModelContext(context.container)
        for model in changed {
            guard let record = model as? any ChangeTimed else { continue }
            stampIfChanged(record, store: store, now: now)
        }
        for model in parts {
            guard let part = model as? any PartOfChangeTimed else { continue }
            stampWhole(of: part, in: context, store: store, now: now)
        }
    }

    /// The values and links a record keeps itself, without its change time.
    static func ownState<M: UndoableRecord>(of record: M) -> [String: StoredValue] {
        var state: [String: StoredValue] = [:]
        for property in M.storedProperties where property.isOwn && property.name != "updatedAt" {
            state[property.name] = property.read(record)
        }
        return state
    }

    private static func stampIfChanged<M: ChangeTimed>(_ record: M, store: ModelContext, now: Date) {
        // Not in the store yet: made by this step, with the time it was made.
        guard let stored = M.find(record.recordKey, in: store) else { return }
        // The step gave it a time of its own.
        guard record.updatedAt == stored.updatedAt else { return }
        guard ownState(of: record) != ownState(of: stored) else { return }
        record.updatedAt = now
    }

    private static func stampWhole<M: PartOfChangeTimed>(of part: M, in context: ModelContext, store: ModelContext, now: Date) {
        // The record it belongs to now, or, for a part taken away, the one it belonged to.
        var refs: [RecordRef] = []
        if case .one(let ref?) = RecordState.capture(part).values[M.wholeProperty] { refs.append(ref) }
        if let stored = M.find(part.recordKey, in: store), case .one(let ref?) = RecordState.capture(stored).values[M.wholeProperty] {
            refs.append(ref)
        }
        for ref in Set(refs) {
            guard let whole = UndoableRecords.find(ref, in: context) as? any ChangeTimed else { continue }
            touch(whole, store: store, now: now)
        }
    }

    private static func touch<M: ChangeTimed>(_ whole: M, store: ModelContext, now: Date) {
        // Made by this step, or given a time by it: nothing to add.
        guard let stored = M.find(whole.recordKey, in: store), whole.updatedAt == stored.updatedAt else { return }
        whole.updatedAt = now
    }
}

extension DosarSchemaV8.Asset: ChangeTimed {}
extension DosarSchemaV8.Obligation: ChangeTimed {}
extension DosarSchemaV8.HistoryEntry: ChangeTimed {}
extension DosarSchemaV8.ServiceItem: ChangeTimed {}
extension DosarSchemaV8.MeasurementLog: ChangeTimed {}
extension DosarSchemaV8.Attachment: ChangeTimed {}
extension DosarSchemaV8.Provider: ChangeTimed {}
extension DosarSchemaV8.CategoryTemplate: ChangeTimed {}

extension DosarSchemaV8.AttachmentPage: PartOfChangeTimed {
    static var wholeProperty: String { "attachment" }
}
