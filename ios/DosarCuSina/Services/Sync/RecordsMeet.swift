import Foundation
import SwiftData

/// Records that share an id are one record, and become one: the one step that joins them, for
/// every model of the schema.
///
/// The same binder on two devices has the same ids: a backup brought from one to the other
/// ("Înlocuiește tot" before sync was on) is the binder's records with their own ids. iCloud
/// keeps each device's record as a record of its own, so with sync on both devices get two
/// copies of every section, deadline, document and firm. This step finds every id held by more
/// than one record and keeps one, on every device the same one, so their results meet:
///
/// - **Which copy stays** is decided only by what never changes and is the same on every device:
///   which copy it is (`copyID`, given by the device that made the copy, never in a backup). The
///   copy with the smallest stays. Never by a change time, which a device may not have received
///   yet: two devices deciding at once must delete the same copy, or both copies would go.
/// - **What it keeps** is the backup's rule for a record on both sides (`ArchiveMerge`): the
///   newer copy's values and links, change times included; with the same change time, the copy
///   that stays keeps its own. Every record that pointed at either copy (a section's history,
///   a firm's jobs, a document's later version) points at the one that stays; a list a record
///   keeps of its own (a firm's sections, a visit's firms) keeps both copies' records; a
///   document's pages are the newer copy's (`StoredProperty.meet`). Then the other copies go.
/// - **A copy from before version 13** has no `copyID` yet. Only the device that made it gives
///   it one, when it meets another copy: a device can't tell which of two equal copies another
///   device made, and two devices naming the same copy differently would decide differently.
///   This device made every copy the store's history doesn't show arriving from iCloud
///   (`PersistenceController.localAuthor`). A group with a copy not yet named by its device
///   waits until that copy's name arrives.
///
/// It is the app's own step: what it writes gives no change time (`ChangeOrigin.restoring`),
/// and it runs at launch, before the repair list, and with every change that arrives from
/// iCloud (`SyncedChanges.settle`), before the built-in categories, once what is on its way has
/// arrived (`CloudArrival`): a record still arriving may point at a copy. Until then, and for a
/// copy still waiting for its name, nothing traps on copies: everything else that reads records
/// by id takes them as they come (the architecture check's `unique-keys`).
@MainActor
enum RecordsMeet {
    /// Joins every set of records that share an id. Returns whether anything changed.
    @discardableResult
    static func join(in context: ModelContext) throws -> Bool {
        // What still arrives may point at a copy: it is joined once all of it is here.
        guard CloudArrival.of(context.container).isWhole else { return false }
        // Records that aren't parts first, so a document's pages go with the copy that goes.
        let types = UndoableRecords.ordered
        let passes = [types.filter { !($0 is any PartOfChangeTimed.Type) }, types.filter { $0 is any PartOfChangeTimed.Type }]
        return try UnitOfWork.perform(in: context, origin: .restoring) {
            var changed = false
            var made: Set<PersistentIdentifier>?
            var keptFor: [PersistentIdentifier: any PersistentModel] = [:]
            for pass in passes {
                let groups = try pass.flatMap { try copies(of: $0, in: context) }
                guard !groups.isEmpty else { continue }
                // Each device names the copies it made.
                for record in groups.joined() where record.copyID == nil {
                    let elsewhere = try made ?? arrivedFromICloud(in: context)
                    made = elsewhere
                    guard !elsewhere.contains(record.persistentModelID) else { continue }
                    record.copyID = UUID()
                    changed = true
                }
                // Every group whose copies are all named joins into the one that stays.
                var joins: [(kept: any UndoableRecord, others: [any UndoableRecord])] = []
                for group in groups where group.allSatisfy({ $0.copyID != nil }) {
                    let ordered = group.sorted(by: staysBefore)
                    guard let kept = ordered.first else { continue }
                    for record in ordered { keptFor[record.persistentModelID] = kept }
                    joins.append((kept, Array(ordered.dropFirst())))
                }
                for join in joins {
                    meet(join.kept, join.others, keptFor: keptFor, in: context)
                    changed = true
                }
            }
            if changed { try UnitOfWork.save(context) }
            return changed
        }
    }

    /// Every set of more than one record of `type` with the same id, in the order of their id.
    private static func copies<M: UndoableRecord>(of type: M.Type, in context: ModelContext) throws -> [[any UndoableRecord]] {
        let records = try context.fetch(FetchDescriptor<M>()).filter { !$0.isDeleted }
        return Dictionary(grouping: records, by: \.recordKey)
            .filter { $0.value.count > 1 }
            .sorted { $0.key < $1.key }
            .map { $0.value.map { $0 as any UndoableRecord } }
    }

    /// The order copies of one record are kept in: the smallest copy name first, the same on
    /// every device. Two copies with the same name (one copy read twice) by where they are kept.
    private static func staysBefore(_ lhs: any UndoableRecord, _ rhs: any UndoableRecord) -> Bool {
        let left = lhs.copyID?.uuidString ?? "", right = rhs.copyID?.uuidString ?? ""
        if left != right { return left < right }
        return String(describing: lhs.persistentModelID) < String(describing: rhs.persistentModelID)
    }

    /// Joins `others` into `kept`, the oldest change first so the newest copy's values are the
    /// ones left, then deletes them.
    private static func meet<M: UndoableRecord>(_ kept: M, _ others: [any UndoableRecord], keptFor: [PersistentIdentifier: any PersistentModel], in context: ModelContext) {
        let copies = others.compactMap { $0 as? M }.sorted { changeTime(of: $0) < changeTime(of: $1) }
        for other in copies {
            let join = RecordJoin(context: context, otherIsNewer: changeTime(of: other) > changeTime(of: kept), keptCopies: keptFor)
            for property in M.storedProperties where property.name != ChangeTimes.copyMark {
                property.meet(kept, other, join)
            }
            context.delete(other)
        }
    }

    /// When a copy last changed; a record without a change time of its own (a page) is never newer.
    private static func changeTime(of record: any UndoableRecord) -> Date {
        (record as? any ChangeTimed)?.updatedAt ?? ChangeTime.unknown
    }

    /// The records iCloud brought: every record the store's history shows inserted by someone
    /// else than this app. A history that can't be read names nothing as this device's own, so
    /// no copy is ever named by a device that didn't make it.
    private static func arrivedFromICloud(in context: ModelContext) throws -> Set<PersistentIdentifier> {
        guard let transactions = try? context.fetchHistory(HistoryDescriptor<DefaultHistoryTransaction>()) else {
            return Set(try UndoableRecords.ordered.flatMap { try all(of: $0, in: context) })
        }
        var arrived: Set<PersistentIdentifier> = []
        for transaction in transactions where transaction.author != nil && transaction.author != PersistenceController.localAuthor {
            for change in transaction.changes {
                if case .insert = change { arrived.insert(change.changedPersistentIdentifier) }
            }
        }
        return arrived
    }

    private static func all<M: UndoableRecord>(of type: M.Type, in context: ModelContext) throws -> [PersistentIdentifier] {
        try context.fetch(FetchDescriptor<M>()).map(\.persistentModelID)
    }
}

/// What joining two copies of one record knows beside the two (`StoredProperty.meet`): whether
/// the other copy is the newer, the copy of every record that stays, and the context.
struct RecordJoin {
    let context: ModelContext
    /// Whether the copy being joined changed later than the one that stays.
    let otherIsNewer: Bool
    let keptCopies: [PersistentIdentifier: any PersistentModel]

    /// The copy of `record` that stays: itself, unless it is a copy that goes.
    func kept<Record: PersistentModel>(_ record: Record) -> Record {
        (keptCopies[record.persistentModelID] as? Record) ?? record
    }
}
