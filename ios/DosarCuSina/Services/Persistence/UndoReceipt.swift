import Foundation
import SwiftData

/// What an undoable action did, and the receipt that takes it back.
public struct Undoable<Value> {
    public let value: Value
    public let receipt: UndoReceipt
}

/// Why a step couldn't be taken back. Written for the person.
public enum UndoError: LocalizedError, Equatable {
    /// Something the step changed was changed again since (another screen, another action).
    case changedSince
    /// The step was already taken back, or it never finished.
    case unavailable

    public var errorDescription: String? {
        switch self {
        case .changedSince:
            String(localized: "Nu mai pot anula, pentru că între timp s-a schimbat ceva aici. Corectează de mână ce e nevoie.",
                   comment: "Undo refused because the same records were changed after the step.")
        case .unavailable:
            String(localized: "Pasul acesta e deja anulat.", comment: "Undo pressed for a step that was already taken back.")
        }
    }
}

/// Exactly what one step changed in the database, made by the step itself, so the toast's
/// "Anulează" can put everything back as it was: values, links, documents (a kept invoice
/// goes back where it was) and readings (undoing "Gata" removes the reading it recorded).
///
/// A unit of work opened with `UnitOfWork.performUndoable` fills it when it saves: the
/// records it created, and every stored property of the records it changed or deleted,
/// as they were before (read from the store, which holds the state the unit started from).
/// Undo runs in one unit of work and refuses when any of those records changed again
/// since, so it never overwrites something newer.
///
/// A receipt lives in memory, only while the toast offers it. Actions that can't be
/// undone don't return one.
@MainActor
public final class UndoReceipt {
    let context: ModelContext
    /// Records the step created; undo deletes them.
    private(set) var inserted: [RecordRef] = []
    /// Records the step changed or deleted, as they were before it.
    private(set) var before: [RecordRef: RecordState] = [:]
    /// Records the step deleted; undo brings them back.
    private(set) var deleted: Set<RecordRef> = []
    /// Records the step created or changed, as it left them: undo checks they're still so.
    private(set) var after: [RecordRef: RecordState] = [:]
    private(set) var isSealed = false
    private(set) var isUndone = false

    init(context: ModelContext) {
        self.context = context
    }

    /// Whether "Anulează" can take this step back: it saved, changed something, and wasn't taken back yet.
    public var canUndo: Bool {
        isSealed && !isUndone && !(inserted.isEmpty && before.isEmpty)
    }

    /// The records the step touched, for tests and for checking what a step did.
    public var touched: Set<RecordRef> {
        Set(inserted).union(before.keys)
    }

    // MARK: Recording (UnitOfWork)

    /// What the unit is about to save, read before the save while deleted records can still be read.
    struct Pending {
        var insertedRefs: [RecordRef]
        var before: [RecordRef: RecordState]
    }

    /// Reads what the open unit changed, just before it saves. Nil when a record can't be
    /// recorded; the receipt then stays unsealed and offers no undo.
    ///
    /// A delete reaches further than the records it names: what they own goes with them
    /// (a section's deadlines, history and documents, a document's pages, a visit's line
    /// items: the schema's cascade rules), and whatever pointed at them loses the link (a
    /// firm's jobs, what was filed under a section). All of it is read as it was, so undo
    /// brings back exactly what the delete took, whenever the store applies its rules.
    func prepare() -> Pending? {
        context.processPendingChanges()
        let inserted = context.insertedModelsArray
        let changed = context.changedModelsArray
        let deleted = context.deletedModelsArray
        // The store still holds every record as it was when the unit opened.
        let store = ModelContext(context.container)
        var before: [RecordRef: RecordState] = [:]
        func read(_ ref: RecordRef) -> RecordState? {
            if let known = before[ref] { return known }
            guard let stored = UndoableRecords.find(ref, in: store) else { return nil }
            let state = RecordState.capture(stored)
            before[ref] = state
            return state
        }
        for model in changed {
            guard let state = RecordState.capture(any: model) else { return nil }
            _ = read(state.ref)
        }
        // Everything a delete takes: the records named, and what they own, all the way down.
        var removed: [RecordRef: RecordState] = [:]
        var queue: [RecordState] = []
        for model in deleted {
            guard let current = RecordState.capture(any: model) else { return nil }
            queue.append(current)
            if let stored = read(current.ref) { queue.append(stored) }
        }
        while let state = queue.popLast() {
            if removed[state.ref] == nil, let stored = before[state.ref] { removed[state.ref] = stored }
            for ref in UndoableRecords.owned(by: state) where removed[ref] == nil {
                if let owned = read(ref) { queue.append(owned) }
            }
        }
        // And whatever pointed at them, as it was before it lost the link.
        for state in removed.values {
            for ref in state.linked where removed[ref] == nil { _ = read(ref) }
        }
        var insertedRefs: [RecordRef] = []
        for model in inserted {
            guard let state = RecordState.capture(any: model) else { return nil }
            insertedRefs.append(state.ref)
        }
        return Pending(insertedRefs: insertedRefs, before: before)
    }

    /// Completes the receipt once the unit has saved: how the step left every record it
    /// touched, read back from the context, and which of them are gone.
    func seal(_ pending: Pending) {
        inserted = pending.insertedRefs
        before = pending.before
        after = [:]
        deleted = []
        for ref in Set(pending.insertedRefs).union(pending.before.keys) {
            if let record = UndoableRecords.find(ref, in: context) {
                after[ref] = RecordState.capture(record)
            } else if pending.before[ref] != nil {
                deleted.insert(ref)
            }
        }
        // A record written with the value it already had, or only read in case a delete
        // reached it, wasn't changed.
        for (ref, state) in before where after[ref] == state {
            before[ref] = nil
            after[ref] = nil
        }
        isSealed = true
    }

    // MARK: Undo

    /// Puts back everything the step changed, in one unit of work: records it deleted come
    /// back, records it changed get their values and links back, records it created go.
    public func undo() throws {
        guard canUndo else { throw UndoError.unavailable }
        try UnitOfWork.perform(in: context) {
            guard isUnchangedSinceStep() else { throw UndoError.changedSince }
            var brought: [RecordRef: any UndoableRecord] = [:]
            for ref in deleted {
                guard let record = UndoableRecords.insertBlank(ref, in: context) else { throw UndoError.changedSince }
                brought[ref] = record
            }
            let context = context
            let resolve: RecordResolver = { ref in
                if let record = brought[ref] ?? UndoableRecords.find(ref, in: context) { return record }
                return nil
            }
            for (ref, state) in before {
                guard let record = brought[ref] ?? UndoableRecords.find(ref, in: context) else { throw UndoError.changedSince }
                UndoableRecords.restore(record, to: state, resolve: resolve)
            }
            // Last, so nothing that was there before goes with what the step made.
            for ref in inserted {
                if let record = UndoableRecords.find(ref, in: context) { context.delete(record) }
            }
            try UnitOfWork.save(context)
        }
        isUndone = true
    }

    /// Whether every record the step left is still as it left it.
    private func isUnchangedSinceStep() -> Bool {
        for (ref, state) in after {
            guard let record = UndoableRecords.find(ref, in: context), RecordState.capture(record) == state else { return false }
        }
        return deleted.allSatisfy { UndoableRecords.find($0, in: context) == nil }
    }
}
