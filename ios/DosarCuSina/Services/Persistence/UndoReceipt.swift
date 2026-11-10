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
    /// The pictures or files the step took, kept for its undo, can no longer be read.
    case picturesLost

    public var errorDescription: String? {
        switch self {
        case .changedSince:
            String(localized: "Nu mai pot anula, pentru că între timp s-a schimbat ceva aici. Corectează de mână ce e nevoie.",
                   comment: "Undo refused because the same records were changed after the step.")
        case .unavailable:
            String(localized: "Pasul acesta e deja anulat.", comment: "Undo pressed for a step that was already taken back.")
        case .picturesLost:
            String(localized: "Nu mai pot anula, pentru că pozele păstrate pentru asta nu mai sunt pe telefon. Adaugă-le din nou, dacă e nevoie.",
                   comment: "Undo refused because the copies of the pictures a deletion took could not be read back.")
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
/// Pictures and files are known by their digest (`StoredValue.file`); the ones the step takes
/// away (a deleted document's pages, a replaced photo) are kept on disk (`UndoFiles`), never
/// in memory, and what a record still has isn't kept twice.
///
/// Undo takes back only what the step changed, property by property, in one unit of work
/// (`UndoableRecord.takeBack`). It refuses when anything of a record's own state that the step
/// changed was changed again since, or when something came to point since at a record whose
/// own state it changed or that it made (another completion of the same deadline), so it never
/// overwrites or strands something newer. A newer change to another property of the same
/// record stays, and so does what came to point at a record the step only linked to (another
/// deadline of the same section completed from the widget); neither stops it.
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
    /// The pictures and files the step took away, for undo to write back.
    private(set) var files: UndoFiles?
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
        var files: UndoFiles?
    }

    /// Reads what the open unit changed, just before it saves. Nil when a record can't be
    /// recorded, or what the step takes can't be kept; the receipt then stays unsealed and
    /// offers no undo, and the step itself still saves.
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
        let store = PersistenceController.context(in: context.container)
        var before: [RecordRef: RecordState] = [:]
        var stored: [RecordRef: any UndoableRecord] = [:]
        func read(_ ref: RecordRef) -> RecordState? {
            if let known = before[ref] { return known }
            guard let record = UndoableRecords.find(ref, in: store) else { return nil }
            let state = RecordState.capture(record)
            before[ref] = state
            stored[ref] = record
            return state
        }
        for model in changed {
            guard let state = RecordState.links(any: model) else { return nil }
            _ = read(state.ref)
        }
        // Everything a delete takes: the records named, and what they own, all the way down.
        var removed: [RecordRef: RecordState] = [:]
        var queue: [RecordState] = []
        for model in deleted {
            guard let current = RecordState.links(any: model) else { return nil }
            queue.append(current)
            if let state = read(current.ref) { queue.append(state) }
        }
        while let state = queue.popLast() {
            if removed[state.ref] == nil, let state = before[state.ref] { removed[state.ref] = state }
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
            guard let state = RecordState.links(any: model) else { return nil }
            insertedRefs.append(state.ref)
        }
        // The pictures and files the step takes away: all of a removed record's, and the ones a
        // changed record replaces or clears. What a record keeps, the receipt knows by digest.
        var files: UndoFiles?
        do {
            for (ref, state) in before {
                guard let record = stored[ref] else { continue }
                let current = removed[ref] == nil ? UndoableRecords.find(ref, in: context) : nil
                for (digest, data) in record.files(of: state, notIn: current) {
                    let kept = files ?? UndoFiles()
                    files = kept
                    try kept.keep(data, as: digest)
                }
            }
        } catch {
            PersistenceLog.logger.error("The pictures a step takes couldn't be kept for its undo; it offers none.")
            return nil
        }
        return Pending(insertedRefs: insertedRefs, before: before, files: files)
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
        files = pending.files
        files?.keepOnly(filesToWriteBack)
        if files?.kept.isEmpty == true { files = nil }
        isSealed = true
    }

    /// The pictures and files undo writes back: every one of a deleted record's, and the ones
    /// the step changed on a record it left.
    private var filesToWriteBack: Set<FileDigest> {
        before.reduce(into: []) { digests, entry in
            let (ref, state) = entry
            let names = after[ref].map { state.changed(from: $0) } ?? Set(state.values.keys)
            for name in names {
                if case .file(let digest?) = state.values[name] { digests.insert(digest) }
            }
        }
    }

    // MARK: Undo

    /// Puts back what the step changed, in one unit of work: records it deleted come back,
    /// records it changed get back what it changed, records it created go. Their change times
    /// come back too, unless a newer change gave one since: the unit gives none of its own
    /// (`ChangeOrigin.restoring`).
    public func undo() throws {
        guard canUndo else { throw UndoError.unavailable }
        let needed = filesToWriteBack
        let bytes: [FileDigest: Data]
        if needed.isEmpty {
            bytes = [:]
        } else if let kept = files?.bytes(of: needed) {
            bytes = kept
        } else {
            throw UndoError.picturesLost
        }
        try UnitOfWork.perform(in: context, origin: .restoring) {
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
            let sources = RestoreSources(record: resolve, file: { bytes[$0] })
            for (ref, state) in before {
                guard let record = brought[ref] ?? UndoableRecords.find(ref, in: context) else { throw UndoError.changedSince }
                record.takeBack(to: state, from: deleted.contains(ref) ? nil : after[ref], sources: sources)
            }
            // Last, so nothing that was there before goes with what the step made.
            for ref in inserted {
                if let record = UndoableRecords.find(ref, in: context) { context.delete(record) }
            }
            try UnitOfWork.save(context)
        }
        isUndone = true
        files?.removeAll()
        files = nil
    }

    /// Whether every record the step left still holds what the step changed, nothing points at
    /// a record it made or whose own state it changed that didn't then, and every record it
    /// deleted is still gone: in this context and in the store under it, where a change from the
    /// person's other devices lands before this context reads it (`SyncedChanges`). Undo never
    /// takes back what another device changed since.
    private func isUnchangedSinceStep() -> Bool {
        let store = PersistenceController.context(in: context.container)
        for (ref, state) in after {
            for place in [context, store] {
                guard let record = UndoableRecords.find(ref, in: place), record.isStillAsLeft(before: before[ref], after: state) else { return false }
            }
        }
        return deleted.allSatisfy { UndoableRecords.find($0, in: context) == nil && UndoableRecords.find($0, in: store) == nil }
    }
}
