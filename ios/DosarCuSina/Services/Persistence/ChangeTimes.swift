import Foundation
import SwiftData

/// When a record last changed: the one value a backup brought in with "Adaugă" compares to
/// keep the newer copy of a record that is on both sides (`ArchiveMerge`).
public enum ChangeTime {
    /// The change time of a record from before it was kept (a history entry, a line item, a
    /// reading or a document saved before version 8, or one from a backup that carries none),
    /// and of a built-in category nobody has changed: older than any change, and the same on
    /// every phone, so two copies of a record nobody has changed since are never taken for a
    /// newer one. Equal to the default the schema gives those records (`DosarSchemaV9`).
    public static let unknown = Date.distantPast
}

/// Whose change a unit of work saves, which decides the change times it gives (`ChangeTimes`).
public enum ChangeOrigin: Sendable, Equatable {
    /// The person's own step (an edit, a filing, "Gata", a reorder): what it changes gets a new
    /// change time.
    case person
    /// What the app does by itself to keep the binder right (the catalog's categories at
    /// launch, the repair list, the household's own deadlines): it changes no record's time,
    /// so a copy of the record that carries the person's change, on this phone or in a backup,
    /// is never taken for the older one. What it makes still gets the time it was made.
    case app
    /// Undo, putting records back as they were, change times included: no time is given.
    case restoring
}

/// A record that keeps when it last changed (`updatedAt`): sections, deadlines, firms,
/// categories, history entries, line items, readings and documents.
public protocol ChangeTimed: UndoableRecord {
    var updatedAt: Date { get set }
    /// Whether a change to the stored property `name` is a change of this record: every one of
    /// its own, unless the record says otherwise (a built-in category).
    func changeCounts(_ name: String) -> Bool
    /// The change time of the record when a step makes it at `now`: `now`, unless the record
    /// says otherwise (a built-in category).
    func changeTime(madeAt now: Date) -> Date
}

extension ChangeTimed {
    public func changeCounts(_ name: String) -> Bool { true }
    public func changeTime(madeAt now: Date) -> Date { now }
}

/// A record that is part of another and keeps no change time of its own: changing it is a
/// change to the record it belongs to (a document's page is a change to the document).
protocol PartOfChangeTimed: UndoableRecord {
    /// The stored relationship to the record it belongs to.
    static var wholeProperty: String { get }
}

/// The one rule for change times, kept by `UnitOfWork` as it saves, and the only code that
/// writes them, beside a backup's importer (the architecture check's
/// `change-time-outside-change-times`).
///
/// - In the person's step (`ChangeOrigin.person`), a record whose own values or links changed
///   gets the step's time (`now`). A record only linked to (a section that got a new visit)
///   hasn't changed: the visit keeps the link. A record whose values were written again as
///   they were hasn't changed either.
/// - Records a step makes have the time they were made, whoever made them.
/// - A step the app takes by itself (`.app`) changes no record's time.
/// - Undo (`.restoring`) puts the old times back with everything else, so a step taken back
///   is as if it never happened.
///
/// A built-in category is the app's own definition, the same on every phone: only what the
/// person chooses for it (its place on the binder, whether it shows there, its lock) is a
/// change of it, and one the catalog installs starts with no change at all
/// (`ChangeTime.unknown`).
///
/// A backup's own writer (`UnitOfWork.performPrivate`) keeps the times the backup carries.
enum ChangeTimes {
    /// Gives the change times a save calls for: `now` to every record the step made, and, for
    /// the person's step, to every record whose own values or links changed and to the record
    /// each changed part belongs to.
    static func stamp(_ context: ModelContext, origin: ChangeOrigin, now: Date) {
        guard origin != .restoring else { return }
        context.processPendingChanges()
        for model in context.insertedModelsArray {
            guard let record = model as? any ChangeTimed else { continue }
            made(record, now: now)
        }
        guard origin == .person else { return }
        let changed = context.changedModelsArray
        let parts = changed + context.insertedModelsArray + context.deletedModelsArray
        guard !changed.isEmpty || !parts.isEmpty else { return }
        // The store still holds every record as it was before these changes.
        let store = PersistenceController.context(in: context.container)
        for model in changed {
            guard let record = model as? any ChangeTimed else { continue }
            stampIfChanged(record, store: store, now: now)
        }
        for model in parts {
            guard let part = model as? any PartOfChangeTimed else { continue }
            stampWhole(of: part, in: context, store: store, now: now)
        }
    }

    /// The values and links a record keeps itself that count as a change of it, without its
    /// change time.
    static func ownState<M: ChangeTimed>(of record: M) -> [String: StoredValue] {
        var state: [String: StoredValue] = [:]
        for property in M.storedProperties where property.isOwn && property.name != "updatedAt" && record.changeCounts(property.name) {
            state[property.name] = property.read(record)
        }
        return state
    }

    private static func made<M: ChangeTimed>(_ record: M, now: Date) {
        record.updatedAt = record.changeTime(madeAt: now)
    }

    private static func stampIfChanged<M: ChangeTimed>(_ record: M, store: ModelContext, now: Date) {
        // Not in the store yet: made by this step, with the time it was made.
        guard let stored = M.find(record.recordKey, in: store) else { return }
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
        // Made by this step: it already has the time it was made.
        guard M.find(whole.recordKey, in: store) != nil else { return }
        whole.updatedAt = now
    }
}

extension DosarSchemaV9.Asset: ChangeTimed {}
extension DosarSchemaV9.Obligation: ChangeTimed {}
extension DosarSchemaV9.HistoryEntry: ChangeTimed {}
extension DosarSchemaV9.ServiceItem: ChangeTimed {}
extension DosarSchemaV9.MeasurementLog: ChangeTimed {}
extension DosarSchemaV9.Attachment: ChangeTimed {}
extension DosarSchemaV9.Provider: ChangeTimed {}

extension DosarSchemaV9.CategoryTemplate: ChangeTimed {
    /// What the person chooses for a built-in category; everything else is the catalog's.
    static let personsOwnChoices: Set<String> = ["homeOrder", "isOnHome", "isSensitive"]

    public func changeCounts(_ name: String) -> Bool {
        !isBuiltIn || Self.personsOwnChoices.contains(name)
    }

    public func changeTime(madeAt now: Date) -> Date {
        isBuiltIn ? ChangeTime.unknown : now
    }
}

extension DosarSchemaV9.AttachmentPage: PartOfChangeTimed {
    static var wholeProperty: String { "attachment" }
}
