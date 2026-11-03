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
                        .task { start(with: container) }
                case .waitingForUnlock:
                    StoreWaitingView()
                case .failed(let failure):
                    StoreRecoveryView(failure: failure, retry: persistence.retry, startFresh: persistence.startFresh)
                }
            }
            .environment(navigator)
            .environment(preferences)
            .environment(vault)
            // The binder speaks Romanian and writes dates and money the Romanian way.
            .environment(\.locale, .dosarDefault)
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
            default:
                break
            }
        }
    }

    /// Installs built-in categories, looks for data to repair and starts the side-effects
    /// pipeline, once per container.
    private func start(with container: ModelContainer) {
        guard sideEffects == nil else { return }
        _ = try? TemplateStore(context: container.mainContext).installBuiltIns()
        // The repair list: steps that change nothing anyone sees run now; the rest wait for
        // the owner, and the shell's calm prompt says when there is something new.
        try? DataRepairCenter.shared.refresh(in: container.mainContext, announce: true)
        if (try? HouseholdRules.reconcile(in: container.mainContext, today: CalendarDay(Date()))) == true {
            try? container.mainContext.save()
        }
        // Capture recognizes documents already in the binder by their fingerprint.
        Task {
            await CaptureDocumentStore.shared().setDuplicateLookup { fingerprint in
                await MainActor.run { AttachmentActions(context: container.mainContext).attachmentID(withFingerprint: fingerprint) }
            }
        }
        DocumentFileProtection.apply(toStoreAt: PersistenceController.defaultStoreURL)
        // The same coordinator notification buttons, widgets, Siri and the background refresh use.
        let coordinator = SideEffectsCoordinator.shared(for: container)
        coordinator.start()
        sideEffects = coordinator
    }
}
