import Foundation
import SwiftData
@preconcurrency import UserNotifications

/// Handles taps and buttons on reminders. "Am rezolvat" and "Amână 3 zile" go
/// through `IntentEngine`, the one way in for actions from outside the app: they
/// act only on the cycle the reminder was about, and reminders are planned again
/// afterwards. A tap opens the obligation through `AppNavigator`.
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
        [.banner, .list, .sound]
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        let request = response.notification.request
        let payload = ReminderPayload(identifier: request.identifier, userInfo: request.content.userInfo, deliveredAt: response.notification.date)
        await handle(action: action, payload: payload)
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
