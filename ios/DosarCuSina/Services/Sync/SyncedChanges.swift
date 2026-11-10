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
@MainActor
final class SyncedChanges {
    /// Posted with `object` the container and the changes as `SearchChanges` under `changesKey`.
    nonisolated static let didArrive = Notification.Name("SyncedChanges.didArrive")
    nonisolated static let changesKey = "changes"

    private let container: ModelContainer
    private var last: DefaultHistoryToken?
    private var listener: Task<Void, Never>?
    private let now: () -> Date

    private static var instance: SyncedChanges?

    static func shared(for container: ModelContainer) -> SyncedChanges {
        if let instance, instance.container === container { return instance }
        instance?.stop()
        let changes = SyncedChanges(container: container)
        instance = changes
        return changes
    }

    init(container: ModelContainer, now: @escaping () -> Date = { Date() }) {
        self.container = container
        self.now = now
        last = Self.latestToken(in: container)
    }

    /// Starts listening to the store's remote changes. Does nothing for a store that doesn't sync.
    func start() {
        guard listener == nil, PersistenceController.syncs(container) else { return }
        listener = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange) {
                self?.read()
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    /// Reads what came since the last read and tells everyone that follows the binder.
    func read() {
        guard let (changes, token) = try? Self.changes(in: container, after: last) else { return }
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
