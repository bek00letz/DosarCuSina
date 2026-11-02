import Foundation
import SwiftData
@preconcurrency import UserNotifications

/// Handles taps and buttons on reminders. "Am rezolvat" and "Amână 3 zile" go
/// through `ObligationActions`, exactly like the same buttons inside the app;
/// a tap opens the obligation through `AppNavigator`.
@MainActor
public final class NotificationResponder: NSObject, UNUserNotificationCenterDelegate {
    private let containerProvider: @MainActor () -> ModelContainer?
    private let navigator: AppNavigator

    public init(
        containerProvider: @escaping @MainActor () -> ModelContainer? = { PersistenceController.shared.container },
        navigator: AppNavigator = .shared
    ) {
        self.containerProvider = containerProvider
        self.navigator = navigator
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        let info = response.notification.request.content.userInfo
        let obligationId = (info[ReminderActions.obligationIdKey] as? String).flatMap(UUID.init(uuidString:))
        let deepLink = (info[ReminderActions.deepLinkKey] as? String).flatMap(URL.init(string:))
        await handle(action: action, obligationId: obligationId, deepLink: deepLink)
    }

    /// Applies a reminder action. Internal so tests can drive it without a notification.
    func handle(action: String, obligationId: UUID?, deepLink: URL?) async {
        switch action {
        case ReminderActions.complete, ReminderActions.snooze:
            guard let obligationId, let container = containerProvider() else { return }
            let context = container.mainContext
            var descriptor = FetchDescriptor<Obligation>(predicate: #Predicate { $0.id == obligationId })
            descriptor.fetchLimit = 1
            guard let obligation = try? context.fetch(descriptor).first else { return }
            let actions = ObligationActions(context: context)
            if action == ReminderActions.complete {
                _ = try? actions.complete(obligation)
            } else {
                try? actions.snooze(obligation, days: ReminderActions.snoozeDays)
            }
        default:
            if let deepLink, navigator.open(deepLink) { return }
            if let obligationId { navigator.open(.obligation(obligationId)) }
        }
    }
}
