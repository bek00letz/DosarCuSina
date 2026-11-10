import Foundation
import SwiftData
import Observation

/// Something else that is rebuilt from the database after every save: the Spotlight
/// index (`SpotlightIndexer`, registered by `SideEffectsCoordinator.shared(for:)`).
/// Register it with `SideEffectsCoordinator.register(_:)`. It gets what may leave the
/// app (`ObligationSnapshot.fetchForOutside`), never examples.
@MainActor
public protocol SideEffectIndexer: AnyObject {
    func reconcile(obligations: [ObligationSnapshot], context: ModelContext) async
}

/// The one path from saved data to everything outside the database: pending
/// reminders, the app badge, the widget snapshot and Spotlight. Views and actions never
/// schedule anything themselves; they save, and this runs after the save.
///
/// It also follows the notice the share extension leaves (`InboxNotice`, the one
/// notification posted outside it): each pass withdraws it once none of the items it
/// announced still waits in the share inbox.
///
/// Triggers: every `ModelContext.didSave` (debounced), preference changes, the
/// day changing, the share inbox changing (`ShareInbox.didChangeNotification`),
/// `reconcileNow()` when the app becomes active, every action from
/// outside the app (`IntentEngine`) and the background refresh.
///
/// There is one per database (`shared(for:)`), and its passes run one after
/// another, so two reconcilers never work on the notification center at once.
@MainActor
@Observable
public final class SideEffectsCoordinator {
    /// Shown in Settings.
    public private(set) var reminderAuthorization: ReminderAuthorization = .notDetermined
    public private(set) var lastReconciledAt: Date?
    /// What the last pass did, or why it couldn't run.
    public private(set) var lastOutcome: NotificationReconciler.Outcome?
    public private(set) var lastFailure: String?

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let reconciler: NotificationReconciler
    @ObservationIgnored private let widgetWriter: WidgetSnapshotWriter
    @ObservationIgnored private let inboxNotices: any InboxNoticeCenter
    @ObservationIgnored private let waitingInboxItems: @MainActor () -> Set<UUID>?
    @ObservationIgnored private let preferences: AppPreferences
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var indexers: [any SideEffectIndexer] = []
    @ObservationIgnored private var observers: [Task<Void, Never>] = []
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var pendingAllowsPrompt = false
    @ObservationIgnored private var inFlight: Task<Void, Never>?

    @ObservationIgnored private static var instance: SideEffectsCoordinator?

    /// The coordinator for this database: the app's own when it is running, so
    /// intents, notification buttons, widget taps and the background refresh all
    /// go through the same one.
    /// It indexes Spotlight with the app's one indexer (`SpotlightIndexer`), whichever of
    /// them made it first.
    public static func shared(for container: ModelContainer) -> SideEffectsCoordinator {
        if let instance, instance.container === container { return instance }
        instance?.stop()
        let coordinator = SideEffectsCoordinator(container: container)
        coordinator.register(SpotlightIndexer())
        instance = coordinator
        return coordinator
    }

    /// The running coordinator, if the app has made one.
    public static var running: SideEffectsCoordinator? { instance }

    /// Delay that folds bursts of saves (an import, a batch edit) into one pass.
    public static let debounce: Duration = .milliseconds(300)

    public init(
        container: ModelContainer,
        notificationClient: any NotificationCenterClient = SystemNotificationCenterClient(),
        widgetWriter: WidgetSnapshotWriter = WidgetSnapshotWriter(),
        inboxNotices: any InboxNoticeCenter = SystemInboxNoticeCenter(),
        waitingInboxItems: @escaping @MainActor () -> Set<UUID>? = { ShareInbox.shared().map { Set($0.waitingItems().map(\.id)) } },
        preferences: AppPreferences = .shared,
        calendar: Calendar = .dosar,
        now: @escaping () -> Date = { Date() }
    ) {
        self.container = container
        self.reconciler = NotificationReconciler(client: notificationClient)
        self.widgetWriter = widgetWriter
        self.inboxNotices = inboxNotices
        self.waitingInboxItems = waitingInboxItems
        self.preferences = preferences
        self.calendar = calendar
        self.now = now
    }

    /// Starts listening for saves and other triggers, registers notification actions,
    /// and runs a first pass (without asking for permission).
    public func start() {
        guard observers.isEmpty else { return }
        // Saves never ask by themselves: the question comes only after the
        // in-app explanation or from Settings, via `askForPermission()`.
        observers.append(listen(to: ModelContext.didSave, allowPrompt: false))
        observers.append(listen(to: AppPreferences.didChangeNotification, allowPrompt: false))
        observers.append(listen(to: .NSCalendarDayChanged, allowPrompt: false))
        observers.append(listen(to: ShareInbox.didChangeNotification, allowPrompt: false))
        // What came from the person's other devices: their reminders, badge, widgets and Spotlight too.
        observers.append(listen(to: SyncedChanges.didArrive, allowPrompt: false))
        // A section locked or opened on this device: what may show outside follows it.
        observers.append(listen(to: SectionLocks.didChange, allowPrompt: false))
        let client = reconciler.client
        Task { await client.registerCategories() }
        setNeedsReconcile(allowPermissionPrompt: false)
    }

    /// Whether this is the coordinator of `container`.
    public func isFollowing(_ container: ModelContainer) -> Bool { self.container === container }

    /// Stops listening: the store opened again under another container (sync turned on or off),
    /// whose own coordinator follows it from now on.
    public func stop() {
        for observer in observers { observer.cancel() }
        observers = []
        pending?.cancel()
        pending = nil
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

    /// After the in-app explanation, or from Settings: a pass now that may ask for notification
    /// permission. It returns once the pass has run, so with the person's answer when the
    /// system asked; screens read the permission again then, never after a guessed pause.
    /// A pass already waiting folds into this one.
    @discardableResult
    public func askForPermission() async -> ReminderAuthorization {
        pending?.cancel()
        pending = nil
        pendingAllowsPrompt = false
        await reconcileNow(allowPermissionPrompt: true)
        return reminderAuthorization
    }

    /// Rebuilds reminders, badge, widget snapshot and indexes from the database now.
    /// A pass asked for while another runs waits for it, then runs on what is saved.
    public func reconcileNow(allowPermissionPrompt: Bool = false) async {
        let previous = inFlight
        let pass = Task { [weak self] in
            await previous?.value
            await self?.runPass(allowPermissionPrompt: allowPermissionPrompt)
        }
        inFlight = pass
        await pass.value
    }

    private func runPass(allowPermissionPrompt: Bool) async {
        // The share's notice has done its job once nothing it announced still waits.
        // Outside the database, so a store that can't be read doesn't keep it up.
        if let waiting = waitingInboxItems() {
            await InboxNotice.follow(waiting: waiting, center: inboxNotices)
        }
        let context = PersistenceController.context(in: container)
        let outside: [ObligationSnapshot]
        do {
            // Example records are for exploring the app; they never notify, badge or reach widgets.
            outside = try ObligationSnapshot.fetchForOutside(in: context, calendar: calendar)
        } catch {
            lastFailure = String(describing: error)
            return
        }
        let date = now()
        let plan = ReminderPlanner.plan(outside, now: date, calendar: calendar, defaultMinuteOfDay: preferences.reminderMinuteOfDay)
        let badge = AttentionModel.digest(outside, now: date, calendar: calendar).needsActionCount
        let openCycles = Dictionary(
            outside.filter { $0.status == .active }.map { ($0.id, $0.dueDay) },
            uniquingKeysWith: { first, _ in first }
        )

        widgetWriter.write(WidgetFeed.make(from: outside, now: date, calendar: calendar))
        let outcome = await reconciler.apply(plan, badgeCount: badge, openCycles: openCycles, allowPermissionPrompt: allowPermissionPrompt)
        reminderAuthorization = outcome.authorization
        lastOutcome = outcome
        lastFailure = nil
        for indexer in indexers {
            await indexer.reconcile(obligations: outside, context: context)
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
