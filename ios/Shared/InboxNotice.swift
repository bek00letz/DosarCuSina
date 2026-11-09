import Foundation
@preconcurrency import UserNotifications

/// The quiet notification that follows a share: "Am primit 2 acte. Deschide aplicația
/// ca să le pui la locul lor." A tap opens the app at Adaugă › De verificat.
///
/// **The one place outside `SideEffectsCoordinator` that touches the notification
/// center**, and only for this one notice. The share extension runs while the app
/// doesn't, so a flag left for the app's coordinator would only turn into a notification
/// once the person had already opened the app, which is what the notice is for. So:
/// - the share extension posts it (`announce`), only when the person already allowed
///   notifications: it never asks, and never for the practice invoice;
/// - the app's coordinator withdraws it (`follow`), on every pass, once none of the
///   items it announced still waits (filed, dismissed or set aside);
/// - nothing else posts, changes or removes it. The architecture check lets this file,
///   and only this file, reach the notification center outside the coordinator.
public enum InboxNotice {
    /// One notice at a time: a new share replaces the one before.
    public static let identifier = "inbox.waiting"
    static let itemsKey = "inboxItems"
    static let threadIdentifier = "inbox"

    /// What the notice says, and which items it is about.
    public struct Content: Hashable, Sendable {
        public var title: String
        public var body: String
        public var itemIDs: [UUID]
    }

    /// Whether a notification is this notice.
    public static func isNotice(_ identifier: String) -> Bool {
        identifier == Self.identifier
    }

    /// The notice for what waits now, or nil when nothing real waits (only the practice).
    /// It counts documents, not files: photos shared together are one.
    public static func content(waiting: [InboxItem]) -> Content? {
        let real = waiting.filter { !$0.isPractice }
        guard !real.isEmpty else { return nil }
        return Content(title: receivedTitle(real.count), body: body(real.count), itemIDs: real.map(\.id))
    }

    /// "Am primit un act", "Am primit 2 acte": the notice's title, and the share sheet's.
    public static func receivedTitle(_ count: Int) -> String {
        String(localized: "Am primit \(count) acte", table: "Shared", comment: "After a share: how many documents arrived. One is a word: „Am primit un act”.")
    }

    static func body(_ count: Int) -> String {
        String(localized: "Deschide aplicația ca să pui \(count) acte la locul lor.", table: "Shared", comment: "Body of the notice after a share. The count only picks the form: „ca să-l pui la locul lui” for one, „ca să le pui la locul lor” for more.")
    }

    /// What the share sheet tells the person to do next.
    public enum NextStep: Hashable, Sendable {
        /// A notice is on its way: tapping it opens De verificat.
        case tapNotice
        /// No notice (notifications aren't allowed): open the app.
        case openApp
        /// The practice invoice, sent from inside the app: go back to it.
        case practice
    }

    /// The next step after a share that saved `saved`, when a notice was (or wasn't) posted.
    public static func nextStep(saved: [InboxItem], notified: Bool) -> NextStep {
        if !saved.isEmpty, saved.allSatisfy(\.isPractice) { return .practice }
        return notified ? .tapNotice : .openApp
    }

    /// Whether the notice has done its job: none of the items it announced still waits.
    public static func shouldWithdraw(announced: [UUID], waiting: Set<UUID>) -> Bool {
        !announced.contains(where: waiting.contains)
    }

    /// The share extension's side: posts the notice for what waits, replacing the one
    /// before, when the person already allowed notifications. Returns whether it posted.
    @discardableResult
    public static func announce(waiting: [InboxItem], center: any InboxNoticeCenter) async -> Bool {
        guard let content = content(waiting: waiting), await center.isAllowed() else { return false }
        return await center.post(content)
    }

    /// The app's side, run only by `SideEffectsCoordinator`: withdraws the notice, waiting
    /// or shown, once none of the items it announced still waits. Returns whether it did.
    @discardableResult
    public static func follow(waiting: Set<UUID>, center: any InboxNoticeCenter) async -> Bool {
        guard let announced = await center.announced(), shouldWithdraw(announced: announced, waiting: waiting) else { return false }
        await center.withdraw()
        return true
    }

    static func userInfo(for content: Content) -> [String: String] {
        [itemsKey: content.itemIDs.map(\.uuidString).joined(separator: ",")]
    }

    static func itemIDs(from userInfo: [AnyHashable: Any]) -> [UUID] {
        ((userInfo[itemsKey] as? String) ?? "").split(separator: ",").compactMap { UUID(uuidString: String($0)) }
    }
}

/// The parts of the notification center the inbox notice uses, so tests can swap in a fake.
public protocol InboxNoticeCenter: Sendable {
    /// The person already allowed notifications. Never asks.
    func isAllowed() async -> Bool
    func post(_ content: InboxNotice.Content) async -> Bool
    /// The items the notice on the phone (waiting or shown) is about; nil when there is none.
    func announced() async -> [UUID]?
    /// Removes the notice, waiting or shown.
    func withdraw() async
}

/// The live notice center, backed by `UNUserNotificationCenter`.
public struct SystemInboxNoticeCenter: InboxNoticeCenter {
    public init() {}

    private var center: UNUserNotificationCenter { .current() }

    public func isAllowed() async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: true
        case .notDetermined, .denied: false
        @unknown default: false
        }
    }

    public func post(_ content: InboxNotice.Content) async -> Bool {
        let notice = UNMutableNotificationContent()
        notice.title = content.title
        notice.body = content.body
        // Quiet: a banner the person can tap, no sound, never through Focus.
        notice.sound = nil
        notice.interruptionLevel = .active
        notice.threadIdentifier = InboxNotice.threadIdentifier
        notice.userInfo = InboxNotice.userInfo(for: content)
        do {
            try await center.add(UNNotificationRequest(identifier: InboxNotice.identifier, content: notice, trigger: nil))
            return true
        } catch {
            return false
        }
    }

    public func announced() async -> [UUID]? {
        let waiting = await center.pendingNotificationRequests().filter { InboxNotice.isNotice($0.identifier) }.map(\.content)
        let shown = await center.deliveredNotifications().filter { InboxNotice.isNotice($0.request.identifier) }.map(\.request.content)
        guard let content = (waiting + shown).first else { return nil }
        return InboxNotice.itemIDs(from: content.userInfo)
    }

    public func withdraw() async {
        center.removePendingNotificationRequests(withIdentifiers: [InboxNotice.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [InboxNotice.identifier])
    }
}
