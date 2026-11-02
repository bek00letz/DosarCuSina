import Foundation
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
/// Work that must only happen once the changes are kept, such as releasing a
/// capture's pages, goes in `afterCommit(in:_:)`.
@MainActor
public enum UnitOfWork {
    private final class Scope {
        var afterCommit: [@MainActor () async -> Void] = []
    }

    private static var open: [ObjectIdentifier: Scope] = [:]

    /// Makes the next commit of a unit fail, so tests can check that a failed
    /// save leaves nothing behind. Cleared after one use.
    static var failNextCommitForTesting: (any Error)?

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
            context.rollback()
            throw error
        }
    }

    /// Runs `work` as one step: the actions inside it don't save on their own,
    /// and the unit saves once at the end. If `work` throws or the save fails,
    /// every change made inside it is rolled back and the error is rethrown.
    /// A unit opened inside another one joins it.
    public static func perform<T>(in context: ModelContext, _ work: () async throws -> T) async throws -> T {
        guard let scope = begin(context) else { return try await work() }
        let result: T
        do {
            result = try await work()
        } catch {
            abort(context)
            throw error
        }
        try commit(context)
        for action in scope.afterCommit { await action() }
        return result
    }

    /// The same as `perform(in:_:)`, for work that doesn't wait on anything.
    public static func perform<T>(in context: ModelContext, _ work: () throws -> T) throws -> T {
        guard let scope = begin(context) else { return try work() }
        let result: T
        do {
            result = try work()
        } catch {
            abort(context)
            throw error
        }
        try commit(context)
        if !scope.afterCommit.isEmpty {
            let actions = scope.afterCommit
            Task { @MainActor in for action in actions { await action() } }
        }
        return result
    }

    /// Opens a unit on the context, or returns nil when one is already open (the caller joins it).
    private static func begin(_ context: ModelContext) -> Scope? {
        let key = ObjectIdentifier(context)
        guard open[key] == nil else { return nil }
        let scope = Scope()
        open[key] = scope
        return scope
    }

    /// Saves everything the unit recorded and closes it; on failure, rolls all of it back.
    private static func commit(_ context: ModelContext) throws {
        do {
            if let failure = failNextCommitForTesting {
                failNextCommitForTesting = nil
                throw failure
            }
            try context.save()
            open[ObjectIdentifier(context)] = nil
        } catch {
            abort(context)
            throw error
        }
    }

    /// Discards everything the unit recorded and closes it.
    private static func abort(_ context: ModelContext) {
        open[ObjectIdentifier(context)] = nil
        context.rollback()
    }

    /// Runs `action` once the open unit of work has saved, or right away when
    /// no unit is open. Nothing runs when the unit fails.
    public static func afterCommit(in context: ModelContext, _ action: @escaping @MainActor () async -> Void) async {
        if let scope = open[ObjectIdentifier(context)] {
            scope.afterCommit.append(action)
        } else {
            await action()
        }
    }
}
