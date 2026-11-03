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

/// A reminder already shown, still in Notification Center.
public struct DeliveredReminder: Hashable, Sendable {
    public var identifier: String
    public var obligationId: UUID?
    /// The cycle it was about (see `ReminderPayload.cycle`).
    public var cycle: CalendarDay?

    public init(identifier: String, obligationId: UUID?, cycle: CalendarDay?) {
        self.identifier = identifier
        self.obligationId = obligationId
        self.cycle = cycle
    }
}

/// The parts of the notification center the reconciler uses, as Sendable values,
/// so tests can swap in a fake.
public protocol NotificationCenterClient: Sendable {
    func authorization() async -> ReminderAuthorization
    func requestAuthorization() async -> Bool
    func pending() async -> [PendingReminder]
    func add(_ reminder: PlannedReminder) async throws
    func remove(identifiers: [String]) async
    func delivered() async -> [DeliveredReminder]
    func removeDelivered(identifiers: [String]) async
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
    static let cycleKey = "dueDay"
    static let deepLinkKey = "deepLink"
    static let fingerprintKey = "fingerprint"
}

/// What a reminder carries, read back from a delivered notification.
public struct ReminderPayload: Hashable, Sendable {
    public var obligationId: UUID?
    /// The cycle it is about: the `dueDay` it carries, or, for reminders planned
    /// before they carried it, the cycle its identifier and delivery day give.
    public var cycle: CalendarDay?
    public var deepLink: URL?

    public init(obligationId: UUID?, cycle: CalendarDay?, deepLink: URL? = nil) {
        self.obligationId = obligationId
        self.cycle = cycle
        self.deepLink = deepLink
    }

    public init(identifier: String, userInfo: [AnyHashable: Any], deliveredAt: Date, calendar: Calendar = .current) {
        obligationId = (userInfo[ReminderActions.obligationIdKey] as? String).flatMap(UUID.init(uuidString:))
            ?? ReminderPlanner.obligationId(fromIdentifier: identifier)
        cycle = (userInfo[ReminderActions.cycleKey] as? String).flatMap(CalendarDay.init(isoString:))
            ?? ReminderPlanner.cycle(fromIdentifier: identifier, deliveredOn: CalendarDay(deliveredAt, calendar: calendar), calendar: calendar)
        deepLink = (userInfo[ReminderActions.deepLinkKey] as? String).flatMap(URL.init(string:))
    }
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
        content.threadIdentifier = (reminder.obligationId?.uuidString ?? reminder.identifier).lowercased()
        content.interruptionLevel = reminder.isTimeSensitive ? .timeSensitive : .active
        var info: [String: String] = [
            ReminderActions.deepLinkKey: reminder.deepLink.absoluteString,
            ReminderActions.fingerprintKey: reminder.fingerprint,
        ]
        if let id = reminder.obligationId {
            // Only reminders about a deadline get "Am rezolvat" and "Amână".
            content.categoryIdentifier = ReminderActions.categoryIdentifier
            info[ReminderActions.obligationIdKey] = id.uuidString
        } else {
            content.categoryIdentifier = ""
        }
        if let cycle = reminder.cycle {
            info[ReminderActions.cycleKey] = cycle.isoString
        }
        content.userInfo = info
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        try await center.add(UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger))
    }

    public func remove(identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func delivered() async -> [DeliveredReminder] {
        await center.deliveredNotifications().map { notification in
            let request = notification.request
            let payload = ReminderPayload(identifier: request.identifier, userInfo: request.content.userInfo, deliveredAt: notification.date)
            return DeliveredReminder(identifier: request.identifier, obligationId: payload.obligationId, cycle: payload.cycle)
        }
    }

    public func removeDelivered(identifiers: [String]) async {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    public func setBadgeCount(_ count: Int) async {
        // The badge is a convenience; the count is shown again on the next pass.
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
/// what is missing, leaves the rest alone. Reminders already shown for a cycle
/// that has closed are removed from Notification Center, so their buttons can't
/// be tapped later. It only touches its own identifiers.
public struct NotificationReconciler: Sendable {
    public let client: any NotificationCenterClient

    public init(client: any NotificationCenterClient) {
        self.client = client
    }

    public struct Outcome: Hashable, Sendable {
        public var authorization: ReminderAuthorization
        public var added: Int
        public var removed: Int
        /// Reminders that couldn't be scheduled; the next pass tries again.
        public var failed: Int = 0
        /// Shown reminders cleared from Notification Center.
        public var clearedDelivered: Int = 0
    }

    /// - Parameter allowPermissionPrompt: ask for permission when it was never
    ///   asked and there is something to remind about. Pass true only right after
    ///   the person saved something, so the question comes in context.
    /// - Parameter openCycles: the due day of every obligation that still reminds.
    ///   A shown reminder for any other cycle (done, snoozed past, deleted) is cleared.
    ///   Nil leaves Notification Center alone.
    @discardableResult
    public func apply(_ plan: [PlannedReminder], badgeCount: Int, openCycles: [UUID: CalendarDay]? = nil, allowPermissionPrompt: Bool) async -> Outcome {
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
        var failed = 0
        for reminder in wanted where pendingById[reminder.identifier]?.fingerprint != reminder.fingerprint {
            do {
                try await client.add(reminder)
                added += 1
            } catch {
                failed += 1
            }
        }
        var cleared = 0
        if let openCycles {
            let closed = await client.delivered()
                .filter { $0.identifier.hasPrefix(ReminderPlanner.identifierPrefix) && Self.isClosed($0, openCycles: openCycles) }
                .map(\.identifier)
            if !closed.isEmpty {
                await client.removeDelivered(identifiers: closed)
                cleared = closed.count
            }
        }
        if authorization == .authorized {
            await client.setBadgeCount(badgeCount)
        }
        return Outcome(authorization: authorization, added: added, removed: stale.count, failed: failed, clearedDelivered: cleared)
    }

    /// A shown reminder whose cycle is no longer open. The "open the app" reminder
    /// has done its job once the app has planned again.
    static func isClosed(_ reminder: DeliveredReminder, openCycles: [UUID: CalendarDay]) -> Bool {
        guard let id = reminder.obligationId else { return true }
        guard let open = openCycles[id] else { return true }
        return reminder.cycle.map { $0 != open } ?? false
    }
}
