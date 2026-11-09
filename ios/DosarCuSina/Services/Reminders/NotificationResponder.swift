import Foundation
import SwiftData
@preconcurrency import UserNotifications

/// Handles taps and buttons on reminders. "Am rezolvat" and "Amână 3 zile" go
/// through `IntentEngine`, the one way in for actions from outside the app: they
/// act only on the cycle the reminder was about, and reminders are planned again
/// afterwards. A tap opens the obligation through `AppNavigator`.
///
/// A tap on the share's notice (`InboxNotice`) opens De verificat the same way, after
/// unlocking when the app is locked; while the app is open the notice isn't shown,
/// since the list is right there.
@MainActor
public final class NotificationResponder: NSObject, UNUserNotificationCenterDelegate {
    private let containerProvider: @MainActor () -> ModelContainer?
    private let navigator: AppNavigator
    private let sideEffects: @MainActor (ModelContainer) -> SideEffectsCoordinator
    private let failures: OutsideActionFailures

    public init(
        containerProvider: @escaping @MainActor () -> ModelContainer? = { PersistenceController.shared.container },
        navigator: AppNavigator = .shared,
        sideEffects: @escaping @MainActor (ModelContainer) -> SideEffectsCoordinator = { SideEffectsCoordinator.shared(for: $0) },
        failures: OutsideActionFailures = .shared
    ) {
        self.containerProvider = containerProvider
        self.navigator = navigator
        self.sideEffects = sideEffects
        self.failures = failures
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        InboxNotice.isNotice(notification.request.identifier) ? [.list] : [.banner, .list, .sound]
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        let request = response.notification.request
        if InboxNotice.isNotice(request.identifier) {
            await openInbox()
            return
        }
        let payload = ReminderPayload(identifier: request.identifier, userInfo: request.content.userInfo, deliveredAt: response.notification.date)
        await handle(action: action, payload: payload)
    }

    /// A tap on the share's notice: De verificat, through the navigator (which waits while
    /// the app is locked). Internal so tests can drive it without a notification.
    func openInbox() {
        navigator.open(InboxLanding.route)
    }

    /// Applies a reminder action. Internal so tests can drive it without a notification.
    func handle(action: String, payload: ReminderPayload, calendar: Calendar = .current) async {
        switch action {
        case ReminderActions.complete, ReminderActions.snooze:
            guard let obligationId = payload.obligationId else { return }
            let request = OutsideRequest(
                obligationId: obligationId,
                cycle: payload.cycle,
                action: action == ReminderActions.complete ? .complete : .snooze(days: ReminderActions.snoozeDays),
                surface: .notification
            )
            do {
                try await IntentEngine.perform(request, container: containerProvider(), sideEffects: sideEffects, failures: failures, calendar: calendar)
            } catch {
                // Recorded by the engine; Urmează shows it the next time the app opens.
            }
        default:
            if let deepLink = payload.deepLink, navigator.open(deepLink) { return }
            if let obligationId = payload.obligationId { navigator.open(.obligation(obligationId)) }
        }
    }
}
