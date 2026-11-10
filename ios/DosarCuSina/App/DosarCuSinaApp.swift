import CoreSpotlight
import SwiftUI
import SwiftData
import UserNotifications

@main
struct DosarCuSinaApp: App {
    @State private var persistence = PersistenceController.shared
    @State private var navigator = AppNavigator.shared
    @State private var preferences = AppPreferences.shared
    @State private var vault = BiometricVaultManager.shared
    @State private var sideEffects: SideEffectsCoordinator?
    @Environment(\.scenePhase) private var scenePhase

    /// Kept for the app's lifetime; the notification center holds its delegate weakly.
    private static let notificationResponder = NotificationResponder()

    init() {
        UNUserNotificationCenter.current().delegate = Self.notificationResponder
        BackgroundRefresh.register()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch persistence.state {
                case .ready(let container):
                    AppShell()
                        .modelContainer(container)
                        .environment(\.sideEffects, sideEffects)
                        // Again whenever the store opens under another container (sync turned on or off).
                        .task(id: ObjectIdentifier(container)) { start(with: container) }
                case .waitingForUnlock:
                    StoreWaitingView()
                case .failed(let failure):
                    StoreRecoveryView(failure: failure, retry: persistence.retry, startFresh: persistence.startFresh)
                }
            }
            .environment(navigator)
            .environment(preferences)
            .environment(vault)
            // The binder speaks Romanian, writes dates and money the Romanian way and counts
            // days in the Gregorian calendar, whatever the phone's region and calendar.
            .dosarLocaleAndCalendar()
            .onOpenURL { url in
                navigator.open(url)
            }
            // A result tapped in the iPhone's search opens like a link, after unlocking.
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
                navigator.open(spotlightIdentifier: identifier)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                sideEffects?.setNeedsReconcile(allowPermissionPrompt: false)
            case .background:
                BackgroundRefresh.schedule()
                // A change to whether the binder syncs (the examples went, say) applies once the
                // screen is away, so nothing on it, such as an "Anulează", is cut short.
                persistence.applySyncChoice()
            default:
                break
            }
        }
    }

    /// Installs built-in categories, looks for data to repair and starts the side-effects
    /// pipeline, once per container.
    private func start(with container: ModelContainer) {
        guard sideEffects?.isFollowing(container) != true else { return }
        // Built-in categories, the repair list and the household's own deadlines, each saved
        // through UnitOfWork.
        LaunchData.prepare(in: container.mainContext, today: CalendarDay(Date()))
        // Capture recognizes documents already in the binder by their fingerprint.
        Task {
            await CaptureDocumentStore.shared().setDuplicateLookup { fingerprint in
                await MainActor.run { AttachmentActions(context: container.mainContext).attachmentID(withFingerprint: fingerprint) }
            }
        }
        DocumentFileProtection.apply(toStoreAt: PersistenceController.defaultStoreURL)
        // Copies of documents a share left behind when the app was closed with the share sheet open.
        DocumentShareFiles.removeLeftovers()
        // Pictures an earlier run kept for an undo it can no longer offer.
        UndoFiles.removeLeftovers()
        // The same coordinator notification buttons, widgets, Siri and the background refresh use.
        let coordinator = SideEffectsCoordinator.shared(for: container)
        coordinator.start()
        sideEffects = coordinator
        // What comes from the person's other devices, when the binder syncs.
        SyncedChanges.shared(for: container).start()
    }
}
