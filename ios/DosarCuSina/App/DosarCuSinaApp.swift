import SwiftUI
import SwiftData
import UserNotifications

@main
struct DosarCuSinaApp: App {
    @State private var persistence = PersistenceController.shared
    @State private var navigator = AppNavigator.shared
    @State private var sideEffects: SideEffectsCoordinator?
    @Environment(\.scenePhase) private var scenePhase

    /// Kept for the app's lifetime; the notification center holds its delegate weakly.
    private static let notificationResponder = NotificationResponder()

    init() {
        UNUserNotificationCenter.current().delegate = Self.notificationResponder
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch persistence.state {
                case .ready(let container):
                    DebugRootView()
                        .modelContainer(container)
                        .task { start(with: container) }
                case .failed(let message):
                    StoreRecoveryView(message: message, retry: persistence.retry, startFresh: persistence.startFresh)
                }
            }
            .environment(navigator)
            .onOpenURL { url in
                navigator.open(url)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                sideEffects?.setNeedsReconcile(allowPermissionPrompt: false)
            }
        }
    }

    /// Installs built-in categories and starts the side-effects pipeline, once per container.
    private func start(with container: ModelContainer) {
        guard sideEffects == nil else { return }
        _ = try? TemplateStore(context: container.mainContext).installBuiltIns()
        let coordinator = SideEffectsCoordinator(container: container)
        coordinator.start()
        sideEffects = coordinator
    }
}
