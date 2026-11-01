import Foundation
@preconcurrency import UserNotifications

/// Whether the app may show reminders, in the app's own terms.
public enum ReminderAuthorization: String, Sendable {
    case notDetermined
    case denied
    case authorized
}

/// A pending request as the reconciler sees it.
public struct PendingReminder: Hashable, Sendable {
    public var identifier: String
    public var fingerprint: String?
}

/// The parts of the notification center the reconciler uses, as Sendable values,
/// so tests can swap in a fake.
public protocol NotificationCenterClient: Sendable {
    func authorization() async -> ReminderAuthorization
    func requestAuthorization() async -> Bool
    func pending() async -> [PendingReminder]
    func add(_ reminder: PlannedReminder) async throws
    func remove(identifiers: [String]) async
    func setBadgeCount(_ count: Int) async
    func registerCategories() async
}

/// Notification category and actions shown on reminders.
public enum ReminderActions {
    public static let categoryIdentifier = "OBLIGATION"
    public static let complete = "OBLIGATION_COMPLETE"
    public static let snooze = "OBLIGATION_SNOOZE_3D"
    public static let snoozeDays = 3

    static let obligationIdKey = "obligationId"
    static let deepLinkKey = "deepLink"
    static let fingerprintKey = "fingerprint"
}

/// The live client backed by `UNUserNotificationCenter`.
public struct SystemNotificationCenterClient: NotificationCenterClient {
    public init() {}

    private var center: UNUserNotificationCenter { .current() }

    public func authorization() async -> ReminderAuthorization {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized, .provisional, .ephemeral: return .authorized
        @unknown default: return .denied
        }
    }

    public func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    public func pending() async -> [PendingReminder] {
        await center.pendingNotificationRequests().map {
            PendingReminder(identifier: $0.identifier, fingerprint: $0.content.userInfo[ReminderActions.fingerprintKey] as? String)
        }
    }

    public func add(_ reminder: PlannedReminder) async throws {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.categoryIdentifier = ReminderActions.categoryIdentifier
        content.threadIdentifier = reminder.obligationId.uuidString.lowercased()
        content.interruptionLevel = reminder.isTimeSensitive ? .timeSensitive : .active
        content.userInfo = [
            ReminderActions.obligationIdKey: reminder.obligationId.uuidString,
            ReminderActions.deepLinkKey: reminder.deepLink.absoluteString,
            ReminderActions.fingerprintKey: reminder.fingerprint,
        ]
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        try await center.add(UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger))
    }

    public func remove(identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func setBadgeCount(_ count: Int) async {
        try? await center.setBadgeCount(count)
    }

    public func registerCategories() async {
        let complete = UNNotificationAction(
            identifier: ReminderActions.complete,
            title: String(localized: "Am rezolvat", comment: "Notification action"),
            options: [.authenticationRequired]
        )
        let snooze = UNNotificationAction(
            identifier: ReminderActions.snooze,
            title: String(localized: "Amână 3 zile", comment: "Notification action"),
            options: []
        )
        let category = UNNotificationCategory(
            identifier: ReminderActions.categoryIdentifier,
            actions: [complete, snooze],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: String(localized: "Scadență", comment: "Notification preview placeholder when previews are hidden"),
            options: []
        )
        center.setNotificationCategories([category])
    }
}

/// Makes the pending notifications match a plan: removes what is stale, adds
/// what is missing, leaves the rest alone. It only touches its own identifiers.
public struct NotificationReconciler: Sendable {
    public let client: any NotificationCenterClient

    public init(client: any NotificationCenterClient) {
        self.client = client
    }

    public struct Outcome: Hashable, Sendable {
        public var authorization: ReminderAuthorization
        public var added: Int
        public var removed: Int
    }

    /// - Parameter allowPermissionPrompt: ask for permission when it was never
    ///   asked and there is something to remind about. Pass true only right after
    ///   the person saved something, so the question comes in context.
    @discardableResult
    public func apply(_ plan: [PlannedReminder], badgeCount: Int, allowPermissionPrompt: Bool) async -> Outcome {
        var authorization = await client.authorization()
        if authorization == .notDetermined, allowPermissionPrompt, !plan.isEmpty {
            authorization = await client.requestAuthorization() ? .authorized : .denied
        }

        let pending = await client.pending().filter { $0.identifier.hasPrefix(ReminderPlanner.identifierPrefix) }
        let wanted = authorization == .authorized ? plan : []
        let wantedById = Dictionary(wanted.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        let pendingById = Dictionary(pending.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })

        let stale = pending.filter { wantedById[$0.identifier]?.fingerprint != $0.fingerprint }.map(\.identifier)
        if !stale.isEmpty {
            await client.remove(identifiers: stale)
        }
        var added = 0
        for reminder in wanted where pendingById[reminder.identifier]?.fingerprint != reminder.fingerprint {
            do {
                try await client.add(reminder)
                added += 1
            } catch {
                continue
            }
        }
        if authorization == .authorized {
            await client.setBadgeCount(badgeCount)
        }
        return Outcome(authorization: authorization, added: added, removed: stale.count)
    }
}
