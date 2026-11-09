import Foundation
import OSLog
import SwiftData

/// The one way the engine commits changes, and the way several actions become
/// one step for the person.
///
/// Every action (`AssetActions`, `ObligationActions`, `AttachmentActions`, …)
/// saves through `save(_:)`. On its own, that saves right away. Inside
/// `perform(in:_:)`, actions only record their changes, and the unit saves once
/// at the end: everything or nothing. A failure anywhere in the unit, including
/// the final save, rolls back every change it made, so one "Salvează" never
/// leaves half a filing behind (a person without their document, a section
/// without its photo).
///
/// A unit belongs to the code that opened it, and only to it:
/// - **It never waits.** `perform` takes synchronous work only. Whatever a step
///   needs that takes time (a capture's pages, Face ID, a reading) is gathered
///   before the unit opens. While a unit is open nothing else runs on the main
///   actor, so another screen's save can't slip into it, and it can't be rolled
///   back with it: that save happens before or after, on its own.
/// - **A rollback takes back only the unit's own changes.** Changes someone else
///   left unsaved on the context are saved before the unit opens.
///
/// - **It asks first.** A step's questions for the person (`StepQuestion`: a lower counter,
///   something of theirs in an example) are asked before its unit opens, never from inside
///   it once it has written: a test run stops where one comes too late.
/// - **What it took back can be read again.** After a rollback, the records the unit touched
///   are fetched again, so a screen drawing them next reads them as they were.
///
/// Work that must only happen once the changes are kept goes in `afterCommit(in:_:)`.
///
/// An action the person can take back opens its unit with `performUndoable(in:_:)`,
/// which returns the step's `UndoReceipt`: what the whole unit changed, recorded as it saves.
@MainActor
public enum UnitOfWork {
    private final class Scope {
        var afterCommit: [@MainActor () async -> Void] = []
        /// Filled when the unit saves, when an undoable action ran in it.
        var receipt: UndoReceipt?
    }

    private static var open: [ObjectIdentifier: Scope] = [:]

    /// Commits that tests have asked to fail, by context.
    private static var failingCommits: [ObjectIdentifier: any Error] = [:]

    /// Makes the next commit of a unit on `context` fail, so tests can check that a
    /// failed save leaves nothing behind. Cleared after one use. Kept per context, so
    /// tests running side by side never fail each other's saves.
    static func failNextCommitForTesting(_ error: any Error, in context: ModelContext) {
        failingCommits[ObjectIdentifier(context)] = error
    }

    /// Whether a unit of work is open on this context.
    public static func isOpen(in context: ModelContext) -> Bool {
        open[ObjectIdentifier(context)] != nil
    }

    /// Saves the context, unless a unit of work is open on it, in which case the
    /// unit saves at its end. On failure, rolls back and rethrows.
    public static func save(_ context: ModelContext) throws {
        guard !isOpen(in: context) else { return }
        do {
            try context.save()
        } catch {
            rollBack(context)
            throw error
        }
    }

    /// Runs `work` as one step: the actions inside it don't save on their own,
    /// and the unit saves once at the end. If `work` throws or the save fails,
    /// every change made inside it is rolled back and the error is rethrown.
    /// A unit opened inside another one joins it.
    public static func perform<T>(in context: ModelContext, _ work: () throws -> T) throws -> T {
        guard let scope = try begin(context) else { return try work() }
        let result: T
        do {
            result = try work()
        } catch {
            noteQuestionAskedLate(error, in: context)
            abort(context)
            throw error
        }
        try commit(context, scope: scope)
        if !scope.afterCommit.isEmpty {
            let actions = scope.afterCommit
            Task { @MainActor in for action in actions { await action() } }
        }
        return result
    }

    /// Runs `work` on a context that one task made for itself and nothing else
    /// touches (a backup written away from the main thread), as one step: saved once at
    /// the end, everything rolled back if anything fails. No other save can join it,
    /// because no one else has the context, so it needs no bookkeeping and runs on any
    /// thread. Actions that save through `save(_:)` belong on the main actor's units.
    nonisolated public static func performPrivate<T>(in context: ModelContext, _ work: () throws -> T) throws -> T {
        do {
            let result = try work()
            try context.save()
            return result
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Runs `work` as one step, like `perform(in:_:)`, and returns with its result the
    /// receipt that takes the step back. Opened inside another unit, it joins it, and the
    /// receipt covers that whole unit: the step the person took is the outer one (a filing
    /// that completes a deadline is undone as one filing). The receipt is usable once the
    /// outermost unit has saved.
    public static func performUndoable<T>(in context: ModelContext, _ work: () throws -> T) throws -> Undoable<T> {
        if let scope = open[ObjectIdentifier(context)] {
            let receipt = scope.receipt ?? UndoReceipt(context: context)
            scope.receipt = receipt
            return Undoable(value: try work(), receipt: receipt)
        }
        let receipt = UndoReceipt(context: context)
        let value = try perform(in: context) {
            open[ObjectIdentifier(context)]?.receipt = receipt
            return try work()
        }
        return Undoable(value: value, receipt: receipt)
    }

    /// Opens a unit on the context, or returns nil when one is already open (the caller joins it).
    /// What another screen left unsaved is saved first, so this unit's rollback can't take it.
    private static func begin(_ context: ModelContext) throws -> Scope? {
        let key = ObjectIdentifier(context)
        guard open[key] == nil else { return nil }
        if context.hasChanges { try context.save() }
        let scope = Scope()
        open[key] = scope
        return scope
    }

    /// Saves everything the unit recorded and closes it; on failure, rolls all of it back.
    private static func commit(_ context: ModelContext, scope: Scope) throws {
        do {
            if let failure = failingCommits.removeValue(forKey: ObjectIdentifier(context)) {
                throw failure
            }
            // What an undoable step changed is read before the save, while the store still
            // holds the state the unit started from.
            let pending = scope.receipt?.prepare()
            try context.save()
            open[ObjectIdentifier(context)] = nil
            if let pending { scope.receipt?.seal(pending) }
        } catch {
            abort(context)
            throw error
        }
    }

    /// Discards everything the unit recorded and closes it.
    private static func abort(_ context: ModelContext) {
        open[ObjectIdentifier(context)] = nil
        rollBack(context)
    }

    /// Takes back what the context holds unsaved, then fetches again every record it touched
    /// and every record those pointed at. SwiftData leaves a rolled-back record's
    /// relationships unreadable until it is fetched again: on the iOS 27 simulator, reading a
    /// section's deadlines after a failed visit stopped the test run. Nothing unsaved: nothing
    /// to take back, and nothing is touched.
    private static func rollBack(_ context: ModelContext) {
        guard context.hasChanges else { return }
        context.processPendingChanges()
        var touched = Set<RecordRef>()
        for model in context.insertedModelsArray + context.changedModelsArray + context.deletedModelsArray {
            guard let state = RecordState.capture(any: model) else { continue }
            touched.insert(state.ref)
            touched.formUnion(state.linked)
        }
        context.rollback()
        for ref in touched { _ = UndoableRecords.find(ref, in: context) }
    }

    /// A question thrown after the unit wrote is a step that didn't ask first. While tests run
    /// it stops here, so the test that takes that path fails where it happens; in the app it is
    /// only logged, since the rollback leaves everything readable and a person must never lose
    /// their work to a development check. Ask it before the unit opens (`StepQuestion`).
    private static func noteQuestionAskedLate(_ error: any Error, in context: ModelContext) {
        guard error is any StepQuestion, context.hasChanges else { return }
        let message = "\(type(of: error)) was thrown after the unit of work wrote. Ask it before the unit opens."
        log.fault("\(message, privacy: .public)")
        #if DEBUG
        if isRunningTests { assertionFailure(message) }
        #endif
    }

    private static let log = Logger(subsystem: "com.ar.dosarcusina.app", category: "persistence")

    /// Whether the app is hosting a test run (xcodebuild test sets this).
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Runs `action` once the open unit of work has saved, or right away when
    /// no unit is open. Nothing runs when the unit fails.
    public static func afterCommit(in context: ModelContext, _ action: @escaping @MainActor () async -> Void) {
        if let scope = open[ObjectIdentifier(context)] {
            scope.afterCommit.append(action)
        } else {
            Task { @MainActor in await action() }
        }
    }
}
