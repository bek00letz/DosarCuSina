import CoreData
import Foundation
import SwiftData

/// What came from the person's other devices through iCloud, told to everything that follows
/// the binder outside a screen: the reminders, the badge, the widgets and Spotlight
/// (`SideEffectsCoordinator`) and Caută's index (`SearchIndexStore`).
///
/// A change saved on this phone goes through the unit of work and is announced by its save
/// (`ModelContext.didSave`). A change that came from iCloud is written by the system under the
/// store, never through a context of ours, so nothing of the person's own steps runs for it: no
/// change time is given (it carries the other device's), no card number is masked again (it was
/// masked where it was typed), no "Anulează" is offered for it, and an undo here takes back only
/// what its own step changed (`UndoReceipt`, which leaves a record changed since as it is). The
/// store says such a change came (`NSPersistentStoreRemoteChange`); its history says what it was:
/// every transaction not made by this app (`PersistenceController.localAuthor`) since the last one
/// read (`changes(in:after:)`).
///
/// When one arrives, the app's own steps that keep two devices' binders one run again, each
/// idempotent and choosing the same records on every device (`settle`): one copy of each built-in
/// category, one copy of each household deadline.
///
/// It starts where the store opens (`PersistenceController.followEveryContainer`), not with a
/// screen, so what arrives while the app runs in the background (woken by iCloud, or by the
/// background refresh) reaches the reminders too. The history is read away from the main
/// thread: the store says a change came after every save, the app's own included. It lets go of
/// a container the store no longer runs on (`ContainerHolder`).
@MainActor
final class SyncedChanges: ContainerHolder {
    /// Posted with `object` the container and the changes as `SearchChanges` under `changesKey`.
    nonisolated static let didArrive = Notification.Name("SyncedChanges.didArrive")
    nonisolated static let changesKey = "changes"

    /// Nil once the container was retired.
    private var container: ModelContainer?
    private var last: DefaultHistoryToken?
    private var listener: Task<Void, Never>?
    private let now: () -> Date

    private static var instance: SyncedChanges?

    static func shared(for container: ModelContainer) -> SyncedChanges {
        if let instance, instance.container === container { return instance }
        instance?.stop()
        instance?.container = nil
        let changes = SyncedChanges(container: container)
        instance = changes
        return changes
    }

    init(container: ModelContainer, now: @escaping () -> Date = { Date() }) {
        self.container = container
        self.now = now
        last = Self.latestToken(in: container)
        ContainerRetirement.add(self)
    }

    func containerRetired(_ container: ModelContainer) {
        guard self.container === container else { return }
        stop()
        self.container = nil
        if Self.instance === self { Self.instance = nil }
    }

    /// Starts listening to the store's remote changes. Does nothing for a store that doesn't sync.
    func start() {
        guard listener == nil, let container, PersistenceController.syncs(container) else { return }
        // One read at a time: a notice that comes while one runs waits for it.
        listener = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange).map({ _ in () }) {
                await self?.read()
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    /// Reads what came since the last read, away from the main thread, and tells everyone that
    /// follows the binder.
    func read() async {
        guard let container else { return }
        let request = SyncedHistoryRead(container: container, after: last)
        let read = await Task.detached { request.reading() }.value
        // The store may have opened under another container meanwhile.
        guard self.container === container, let (changes, token) = read.value else { return }
        if let token { last = token }
        guard !changes.isEmpty else { return }
        settle()
        NotificationCenter.default.post(name: Self.didArrive, object: container, userInfo: [Self.changesKey: changes])
    }

    /// The app's own steps that make two devices' binders one: one copy of each built-in category
    /// (`TemplateStore.installBuiltIns`), one copy of each household deadline
    /// (`HouseholdRules.reconcile`). Each chooses the same records on every device, so their
    /// results meet without a conflict.
    func settle() {
        guard let container else { return }
        let context = container.mainContext
        PersistenceLog.attempt("Settling the built-in categories after a synced change") {
            _ = try TemplateStore(context: context).installBuiltIns()
        }
        PersistenceLog.attempt("Settling the household deadlines after a synced change") {
            _ = try LaunchData.reconcileHouseholdRules(in: context, today: CalendarDay(now()))
        }
    }

    // MARK: Reading the history


    /// What every transaction not made by this app wrote after `token` (all of them when nil), and
    /// the last transaction's token.
    nonisolated static func changes(in container: ModelContainer, after token: DefaultHistoryToken?) throws -> (SearchChanges, DefaultHistoryToken?) {
        let context = PersistenceController.context(in: container)
        var descriptor = HistoryDescriptor<DefaultHistoryTransaction>()
        if let token { descriptor.predicate = #Predicate { $0.token > token } }
        let transactions = try context.fetchHistory(descriptor)
        var changes = SearchChanges()
        for transaction in transactions where transaction.author != PersistenceController.localAuthor {
            for change in transaction.changes {
                switch change {
                case .insert, .update: changes.changed.insert(change.changedPersistentIdentifier)
                case .delete: changes.deleted.insert(change.changedPersistentIdentifier)
                // A kind of change this build doesn't know: the record is read again.
                @unknown default: changes.changed.insert(change.changedPersistentIdentifier)
                }
            }
        }
        changes.changed.subtract(changes.deleted)
        return (changes, transactions.map(\.token).max() ?? token)
    }

    /// The newest transaction's token: what came before the app started is read with the binder.
    nonisolated static func latestToken(in container: ModelContainer) -> DefaultHistoryToken? {
        var descriptor = HistoryDescriptor<DefaultHistoryTransaction>(sortBy: [SortDescriptor(\.transactionIdentifier, order: .reverse)])
        descriptor.fetchLimit = 1
        return try? PersistenceController.context(in: container).fetchHistory(descriptor).first?.token
    }
}

/// One read of the history, handed to the thread it runs on and back. A history token is a
/// value, and the container is safe to share.
private struct SyncedHistoryRead: @unchecked Sendable {
    let container: ModelContainer
    let after: DefaultHistoryToken?
    var value: (SearchChanges, DefaultHistoryToken?)?

    init(container: ModelContainer, after: DefaultHistoryToken?) {
        self.container = container
        self.after = after
    }

    func reading() -> SyncedHistoryRead {
        var read = self
        read.value = try? SyncedChanges.changes(in: container, after: after)
        return read
    }
}
