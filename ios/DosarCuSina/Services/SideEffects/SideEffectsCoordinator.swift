import Foundation
import SwiftData
import Observation

/// Something else that is rebuilt from the database after every save, such as a
/// Spotlight index. Register it with `SideEffectsCoordinator.register(_:)`.
@MainActor
public protocol SideEffectIndexer: AnyObject {
    func reconcile(obligations: [ObligationSnapshot], context: ModelContext) async
}

/// The one path from saved data to everything outside the database: pending
/// reminders, the app badge and the widget snapshot. Views and actions never
/// schedule anything themselves; they save, and this runs after the save.
///
/// Triggers: every `ModelContext.didSave` (debounced), preference changes, the
/// day changing, and `reconcileNow()` when the app becomes active.
@MainActor
@Observable
public final class SideEffectsCoordinator {
    /// Shown in Settings.
    public private(set) var reminderAuthorization: ReminderAuthorization = .notDetermined
    public private(set) var lastReconciledAt: Date?

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let reconciler: NotificationReconciler
    @ObservationIgnored private let widgetWriter: WidgetSnapshotWriter
    @ObservationIgnored private let preferences: AppPreferences
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var indexers: [any SideEffectIndexer] = []
    @ObservationIgnored private var observers: [Task<Void, Never>] = []
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var pendingAllowsPrompt = false

    /// Delay that folds bursts of saves (an import, a batch edit) into one pass.
    public static let debounce: Duration = .milliseconds(300)

    public init(
        container: ModelContainer,
        notificationClient: any NotificationCenterClient = SystemNotificationCenterClient(),
        widgetWriter: WidgetSnapshotWriter = WidgetSnapshotWriter(),
        preferences: AppPreferences = .shared,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { Date() }
    ) {
        self.container = container
        self.reconciler = NotificationReconciler(client: notificationClient)
        self.widgetWriter = widgetWriter
        self.preferences = preferences
        self.calendar = calendar
        self.now = now
    }

    /// Starts listening for saves and other triggers, registers notification actions,
    /// and runs a first pass (without asking for permission).
    public func start() {
        guard observers.isEmpty else { return }
        observers.append(listen(to: ModelContext.didSave, allowPrompt: true))
        observers.append(listen(to: AppPreferences.didChangeNotification, allowPrompt: false))
        observers.append(listen(to: .NSCalendarDayChanged, allowPrompt: false))
        let client = reconciler.client
        Task { await client.registerCategories() }
        setNeedsReconcile(allowPermissionPrompt: false)
    }

    public func register(_ indexer: any SideEffectIndexer) {
        indexers.append(indexer)
        setNeedsReconcile(allowPermissionPrompt: false)
    }

    /// Schedules a pass after a short delay; repeated calls fold into one.
    public func setNeedsReconcile(allowPermissionPrompt: Bool) {
        pendingAllowsPrompt = pendingAllowsPrompt || allowPermissionPrompt
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled, let self else { return }
            let allowPrompt = self.pendingAllowsPrompt
            self.pendingAllowsPrompt = false
            await self.reconcileNow(allowPermissionPrompt: allowPrompt)
        }
    }

    /// Rebuilds reminders, badge, widget snapshot and indexes from the database now.
    public func reconcileNow(allowPermissionPrompt: Bool = false) async {
        let context = ModelContext(container)
        guard let obligations = try? ObligationSnapshot.fetchAll(in: context, calendar: calendar) else { return }
        let date = now()
        // Example records are for exploring the app; they never notify, badge or reach widgets.
        let real = obligations.filter { !$0.isExample }
        let plan = ReminderPlanner.plan(real, now: date, calendar: calendar, defaultMinuteOfDay: preferences.reminderMinuteOfDay)
        let badge = AttentionModel.digest(real, now: date, calendar: calendar).needsActionCount

        widgetWriter.write(WidgetSnapshot.make(from: real, now: date, calendar: calendar))
        let outcome = await reconciler.apply(plan, badgeCount: badge, allowPermissionPrompt: allowPermissionPrompt)
        reminderAuthorization = outcome.authorization
        for indexer in indexers {
            await indexer.reconcile(obligations: obligations, context: context)
        }
        lastReconciledAt = date
    }

    private func listen(to name: Notification.Name, allowPrompt: Bool) -> Task<Void, Never> {
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: name).map({ _ in () }) {
                self?.setNeedsReconcile(allowPermissionPrompt: allowPrompt)
            }
        }
    }
}
