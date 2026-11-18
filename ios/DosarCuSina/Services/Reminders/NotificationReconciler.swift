import Foundation
@preconcurrency import UserNotifications

/// Whether the app may show reminders, in the app's own terms. Quiet delivery the system
/// chose (provisional, ephemeral) counts as authorized: the reminders are scheduled, and
/// the phone's Settings is where the person makes them louder.
public enum ReminderAuthorization: String, Sendable {
    case notDetermined
    case denied
    case authorized
}

/// When a pass may ask the system for notification permission. It asks only while the
/// person hasn't decided (`ReminderAuthorization.notDetermined`); once they have, only the
/// phone's Settings changes it.
public enum PermissionPrompt: Sendable {
    /// Passes on their own (saves, the day changing, the app becoming active) never ask.
    case never
    /// Right after the person saved something that reminds: asks only when there is
    /// something to remind about, so the question comes in context.
    case inContext
    /// The person asked for notifications (Settings' "Pornește notificările", the
    /// explanation's "Continuă"): asks whatever is planned, even with nothing to remind about yet.
    case personAsked

    /// Whether a pass with this prompt asks an undecided person, given whether anything is planned.
    public func asks(somethingToRemind: Bool) -> Bool {
        switch self {
        case .never: false
        case .inContext: somethingToRemind
        case .personAsked: true
        }
    }
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
    /// It was written with a locked category's generic words (its category,
    /// `ReminderActions.isProtected(category:)`); otherwise it names the deadline.
    public var isProtected: Bool

    public init(identifier: String, obligationId: UUID?, cycle: CalendarDay?, isProtected: Bool = false) {
        self.identifier = identifier
        self.obligationId = obligationId
        self.cycle = cycle
        self.isProtected = isProtected
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
    /// A reminder about a deadline of a locked category: „Am rezolvat” opens the app, which asks
    /// for Face ID before it closes the deadline; „Amână” works from the Lock Screen as it is.
    public static let protectedCategoryIdentifier = "OBLIGATION_PROTECTED"
    /// A reminder about a deadline whose closing asks a new day or a new document
    /// (`CompletionShape.closesOutsideTheApp`): „Am rezolvat” opens the app's „Am rezolvat”.
    public static let inAppCategoryIdentifier = "OBLIGATION_IN_APP"

    /// What a reminder's category says of its deadline: whether its category is locked on this
    /// device, and whether closing it asks what only the app can ask. One category each, so the
    /// buttons' options follow both and a reminder shown says which it was when it fired.
    struct Kind: Hashable, CaseIterable {
        var isProtected: Bool
        var closesInTheApp: Bool

        static let allCases = [false, true].flatMap { isProtected in
            [false, true].map { Kind(isProtected: isProtected, closesInTheApp: $0) }
        }
    }

    /// The category a reminder about a deadline gets. A locked category's wins: its „Am rezolvat”
    /// opens the app already, and its generic words are what a shown reminder is read by.
    public static func category(isProtected: Bool, closesInTheApp: Bool = false) -> String {
        if isProtected { return protectedCategoryIdentifier }
        return closesInTheApp ? inAppCategoryIdentifier : categoryIdentifier
    }

    /// Whether a shown reminder of this category was written with a locked category's generic words.
    static func isProtected(category: String) -> Bool {
        category == protectedCategoryIdentifier
    }

    /// What „Am rezolvat” asks of the system before the app hears of it: the phone unlocked; the
    /// app on screen for a locked category, so it can ask for Face ID (`DeadlineChange`), and for
    /// a deadline whose closing asks a new day or a new document, which only the app asks.
    static func completeOptions(isProtected: Bool, closesInTheApp: Bool = false) -> UNNotificationActionOptions {
        DeadlineChange.close.asksFaceID(inLockedCategory: isProtected) || closesInTheApp
            ? [.authenticationRequired, .foreground] : [.authenticationRequired]
    }

    /// What „Amână” asks of the system: nothing, locked category or not (`DeadlineChange`), and
    /// whether or not closing needs the app.
    static func snoozeOptions(isProtected: Bool) -> UNNotificationActionOptions {
        DeadlineChange.snooze.asksFaceID(inLockedCategory: isProtected) ? [.authenticationRequired, .foreground] : []
    }
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

    public init(identifier: String, userInfo: [AnyHashable: Any], deliveredAt: Date, calendar: Calendar = .dosar) {
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
        content.badge = reminder.badge.map { NSNumber(value: $0) }
        guard reminder.showsAlert else {
            // Only the badge, as the day starts (`BadgePlanner`): nothing shown, nothing heard.
            content.userInfo = [ReminderActions.fingerprintKey: reminder.fingerprint]
            try await center.add(UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: ReminderTrigger.make(firingAt: reminder.fireDate)))
            return
        }
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
            content.categoryIdentifier = ReminderActions.category(isProtected: reminder.isProtected, closesInTheApp: reminder.closesInTheApp)
            info[ReminderActions.obligationIdKey] = id.uuidString
        } else {
            content.categoryIdentifier = ""
        }
        if let cycle = reminder.cycle {
            info[ReminderActions.cycleKey] = cycle.isoString
        }
        content.userInfo = info
        // In the app's calendar, whatever calendar the phone is set to (`ReminderTrigger`).
        try await center.add(UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: ReminderTrigger.make(firingAt: reminder.fireDate)))
    }

    public func remove(identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func delivered() async -> [DeliveredReminder] {
        await center.deliveredNotifications().map { notification in
            let request = notification.request
            let payload = ReminderPayload(identifier: request.identifier, userInfo: request.content.userInfo, deliveredAt: notification.date)
            return DeliveredReminder(identifier: request.identifier, obligationId: payload.obligationId, cycle: payload.cycle,
                                     isProtected: ReminderActions.isProtected(category: request.content.categoryIdentifier))
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
        // One per kind; a locked one that closes in the app is the locked one (`category`).
        var seen = Set<String>()
        let kinds = ReminderActions.Kind.allCases.filter { seen.insert(ReminderActions.category(isProtected: $0.isProtected, closesInTheApp: $0.closesInTheApp)).inserted }
        let categories = kinds.map { kind in
            let complete = UNNotificationAction(
                identifier: ReminderActions.complete,
                title: String(localized: "Am rezolvat", comment: "Notification action"),
                options: ReminderActions.completeOptions(isProtected: kind.isProtected, closesInTheApp: kind.closesInTheApp)
            )
            let snooze = UNNotificationAction(
                identifier: ReminderActions.snooze,
                title: String(localized: "Amână 3 zile", comment: "Notification action"),
                options: ReminderActions.snoozeOptions(isProtected: kind.isProtected)
            )
            return UNNotificationCategory(
                identifier: ReminderActions.category(isProtected: kind.isProtected, closesInTheApp: kind.closesInTheApp),
                actions: [complete, snooze],
                intentIdentifiers: [],
                hiddenPreviewsBodyPlaceholder: String(localized: "Scadență", comment: "Notification preview placeholder when previews are hidden"),
                options: []
            )
        }
        center.setNotificationCategories(Set(categories))
    }
}

/// Makes the pending notifications match a plan: removes what is stale, adds
/// what is missing, leaves the rest alone. Reminders already shown for a cycle
/// that has closed are removed from Notification Center, so their buttons can't
/// be tapped later, and so are those that name a deadline whose category is locked
/// now: what stays there says no more than a reminder planned now would. It only
/// touches its own identifiers.
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

    /// The permission, after asking the system when `prompt` asks an undecided person
    /// (`PermissionPrompt.asks`, the one rule). It returns once the person answered, with
    /// the permission read again from the system, so a question that didn't show leaves it undecided.
    public func authorization(asking prompt: PermissionPrompt, somethingToRemind: Bool) async -> ReminderAuthorization {
        let current = await client.authorization()
        guard current == .notDetermined, prompt.asks(somethingToRemind: somethingToRemind) else { return current }
        _ = await client.requestAuthorization()
        return await client.authorization()
    }

    /// - Parameter prompt: whether this pass may ask for permission (`PermissionPrompt`).
    /// - Parameter openCycles: the due day of every obligation that still reminds.
    ///   A shown reminder for any other cycle (done, snoozed past, deleted) is cleared.
    ///   Nil leaves Notification Center alone.
    /// - Parameter locked: the obligations whose category is locked on this device now. A shown
    ///   reminder that names one of them (written before its lock was turned on) is cleared:
    ///   one planned now would say only the generic words.
    @discardableResult
    public func apply(_ plan: [PlannedReminder], badgeCount: Int, openCycles: [UUID: CalendarDay]? = nil, locked: Set<UUID> = [],
                      prompt: PermissionPrompt) async -> Outcome {
        let authorization = await self.authorization(asking: prompt, somethingToRemind: plan.contains(where: \.showsAlert))

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
                .filter { $0.identifier.hasPrefix(ReminderPlanner.identifierPrefix) && Self.isOutdated($0, openCycles: openCycles, locked: locked) }
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

    /// A shown reminder that no longer belongs in Notification Center: its cycle closed
    /// (`isClosed`), or it names a deadline whose category is locked now.
    static func isOutdated(_ reminder: DeliveredReminder, openCycles: [UUID: CalendarDay], locked: Set<UUID>) -> Bool {
        if isClosed(reminder, openCycles: openCycles) { return true }
        guard let id = reminder.obligationId else { return false }
        return locked.contains(id) && !reminder.isProtected
    }

    /// A shown reminder whose cycle is no longer open. The "open the app" reminder
    /// has done its job once the app has planned again.
    static func isClosed(_ reminder: DeliveredReminder, openCycles: [UUID: CalendarDay]) -> Bool {
        guard let id = reminder.obligationId else { return true }
        guard let open = openCycles[id] else { return true }
        return reminder.cycle.map { $0 != open } ?? false
    }
}
