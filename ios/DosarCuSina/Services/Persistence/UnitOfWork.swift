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
/// - **It keeps change times, and only it.** Every record whose own values or links the
///   person's step changes gets a new change time as it saves, and what a step makes gets
///   the time it was made (`ChangeTimes`), so a backup brought in later knows which copy is
///   newer. The time is the step's clock (`now`), or the moment it saves. A step the app
///   takes by itself (`ChangeOrigin.app`: the catalog's categories, launch's repairs, the
///   household's own deadlines) gives no record a new time, and undo puts the old ones back
///   (`.restoring`). A backup's own writer (`performPrivate`) keeps the times the backup
///   carries. Nothing else writes a change time.
///
/// - **It keeps card numbers out.** Every card number in the words of every record a save
///   writes (a row under Date importante, a note, a title, a document's text) is masked just
///   before it saves, whoever wrote it, a backup's own writer included (`FreeText`).
///
/// Work that must only happen once the changes are kept goes in `afterCommit(in:_:)`.
///
/// An action the person can take back opens its unit with `performUndoable(in:_:)`,
/// which returns the step's `UndoReceipt`: what the whole unit changed, recorded as it saves.
@MainActor
public enum UnitOfWork {
    private final class Scope {
        /// Whose change the unit saves: the one who opened it (`ChangeOrigin`).
        let origin: ChangeOrigin
        /// The step's clock: the opener's, else the first a step inside it gave; nil, the
        /// moment it saves.
        var now: Date?
        var afterCommit: [@MainActor () async -> Void] = []
        /// Filled when the unit saves, when an undoable action ran in it.
        var receipt: UndoReceipt?

        init(origin: ChangeOrigin, now: Date?) {
            self.origin = origin
            self.now = now
        }
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
    /// unit saves at its end. On failure, rolls back and rethrows. `now` is the step's clock,
    /// the change time it gives (an open unit takes it when it has none of its own).
    public static func save(_ context: ModelContext, now: Date? = nil) throws {
        if let scope = open[ObjectIdentifier(context)] {
            if scope.now == nil { scope.now = now }
            return
        }
        do {
            try write(context, origin: .person, now: now)
        } catch {
            rollBack(context)
            throw error
        }
    }

    /// Runs `work` as one step: the actions inside it don't save on their own,
    /// and the unit saves once at the end. If `work` throws or the save fails,
    /// every change made inside it is rolled back and the error is rethrown.
    /// A unit opened inside another one joins it: the outer unit's `origin` holds (an app-made
    /// step inside the person's is part of the person's step), and `now` is used only when the
    /// outer unit has no clock.
    ///
    /// `origin` says whose change it is (`ChangeOrigin`): the person's by default. `now` is the
    /// step's clock, the change time it gives; without one, the moment it saves.
    public static func perform<T>(
        in context: ModelContext,
        origin: ChangeOrigin = .person,
        now: Date? = nil,
        _ work: () throws -> T
    ) throws -> T {
        guard let scope = try begin(context, origin: origin, now: now) else { return try work() }
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
            FreeText.mask(context)
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
    public static func performUndoable<T>(in context: ModelContext, now: Date? = nil, _ work: () throws -> T) throws -> Undoable<T> {
        if let scope = open[ObjectIdentifier(context)] {
            let receipt = scope.receipt ?? UndoReceipt(context: context)
            scope.receipt = receipt
            if scope.now == nil { scope.now = now }
            return Undoable(value: try work(), receipt: receipt)
        }
        let receipt = UndoReceipt(context: context)
        let value = try perform(in: context, now: now) {
            open[ObjectIdentifier(context)]?.receipt = receipt
            return try work()
        }
        return Undoable(value: value, receipt: receipt)
    }

    /// Opens a unit on the context, or returns nil when one is already open (the caller joins it).
    /// What another screen left unsaved is saved first, so this unit's rollback can't take it.
    private static func begin(_ context: ModelContext, origin: ChangeOrigin, now: Date?) throws -> Scope? {
        let key = ObjectIdentifier(context)
        if let joined = open[key] {
            if joined.now == nil { joined.now = now }
            return nil
        }
        if context.hasChanges { try write(context, origin: .person, now: nil) }
        let scope = Scope(origin: origin, now: now)
        open[key] = scope
        return scope
    }

    /// Saves everything the unit recorded and closes it; on failure, rolls all of it back.
    private static func commit(_ context: ModelContext, scope: Scope) throws {
        do {
            if let failure = failingCommits.removeValue(forKey: ObjectIdentifier(context)) {
                throw failure
            }
            // Card numbers out and change times first, so an undoable step's receipt records them;
            // what it changed is read before the save, while the store still holds the state the
            // unit started from.
            FreeText.mask(context)
            ChangeTimes.stamp(context, origin: scope.origin, now: scope.now ?? Date())
            let pending = scope.receipt?.prepare()
            try context.save()
            open[ObjectIdentifier(context)] = nil
            if let pending { scope.receipt?.seal(pending) }
        } catch {
            abort(context)
            throw error
        }
    }

    /// Saves the context with no card number in it and the change times its changes call for.
    private static func write(_ context: ModelContext, origin: ChangeOrigin, now: Date?) throws {
        FreeText.mask(context)
        ChangeTimes.stamp(context, origin: origin, now: now ?? Date())
        try context.save()
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
        PersistenceLog.logger.fault("\(message, privacy: .public)")
        #if DEBUG
        if isRunningTests { assertionFailure(message) }
        #endif
    }

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
