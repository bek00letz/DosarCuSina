import Foundation
import UIKit

/// Opening the app while something shared waits lands on Adaugă › De verificat, once.
///
/// When the app comes to the front from the background and something arrived that the
/// person hasn't seen in De verificat yet, it opens there through `AppNavigator`, like a
/// link: so only after unlocking when the app is locked. It never fights the person:
/// - a route they are opening wins (a reminder, a link, a widget, a search result, the
///   share's own notice, whose tap opens De verificat anyway);
/// - nothing moves while something is open over the tabs (a sheet, a form, an alert,
///   onboarding);
/// - what De verificat has shown counts as seen (`markSeen`, kept on the phone), so it
///   lands once per arrival, and never for the practice invoice.
@MainActor
final class InboxLanding {
    static let shared = InboxLanding()

    /// De verificat: the top of the Adaugă tab.
    static let route: AppRoute = .intake
    /// How long it lets a notification tap or a link that comes with the app reach the
    /// navigator first.
    static let settle: Duration = .milliseconds(400)
    static let seenThroughKey = "inbox.seenThrough"

    private let defaults: UserDefaults
    private let settleDelay: Duration
    /// A cold start counts as coming from the background.
    private var cameFromBackground = true
    /// The navigator's count when the app last left, so a route opened since is known.
    private var routesBeforeBackground = 0

    init(defaults: UserDefaults = .standard, settle: Duration = InboxLanding.settle) {
        self.defaults = defaults
        self.settleDelay = settle
    }

    /// The newest arrival De verificat has shown.
    var seenThrough: Date? {
        defaults.object(forKey: Self.seenThroughKey) as? Date
    }

    /// What De verificat shows now has been seen.
    func markSeen(_ items: [InboxItem]) {
        guard let newest = items.filter({ !$0.isPractice }).map(\.receivedAt).max(),
              newest > (seenThrough ?? .distantPast) else { return }
        defaults.set(newest, forKey: Self.seenThroughKey)
    }

    /// Whether something real arrived that De verificat hasn't shown yet.
    static func owesLanding(waiting: [InboxItem], seenThrough: Date?) -> Bool {
        waiting.contains { !$0.isPractice && $0.receivedAt > (seenThrough ?? .distantPast) }
    }

    /// The app went to the background.
    func didEnterBackground(navigator: AppNavigator) {
        cameFromBackground = true
        routesBeforeBackground = navigator.openCount
    }

    /// The app is active. After a short beat, opens De verificat when something new waits,
    /// nothing else is being opened and nothing is open over the tabs. Returns whether it did.
    ///
    /// A beat cut short (the app went inactive again, for Face ID) leaves it for the next time.
    @discardableResult
    func didBecomeActive(waiting: () -> [InboxItem], navigator: AppNavigator, isBusy: () -> Bool) async -> Bool {
        guard cameFromBackground else { return false }
        if settleDelay > .zero { try? await Task.sleep(for: settleDelay) }
        guard !Task.isCancelled else { return false }
        cameFromBackground = false
        let routeOpened = navigator.openCount != routesBeforeBackground || navigator.pendingRoute != nil
        guard !routeOpened, Self.owesLanding(waiting: waiting(), seenThrough: seenThrough), !isBusy() else { return false }
        navigator.open(Self.route)
        return true
    }

    /// Something is open over the tabs: a sheet, a full-screen flow or an alert, in the
    /// app's own windows (the lock lives in a window above them and doesn't count).
    static func isShowingSomethingOverTheTabs() -> Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { $0.windowLevel == .normal }
            .contains { $0.rootViewController?.presentedViewController != nil }
    }
}
