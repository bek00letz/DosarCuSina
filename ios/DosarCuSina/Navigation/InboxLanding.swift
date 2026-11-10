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
    static let seenThroughKey = "inbox.seenThrough"

    private let defaults: UserDefaults
    /// How long a route that comes with the app's opening may take to reach the navigator.
    private let opening: Duration
    /// A cold start counts as coming from the background.
    private var cameFromBackground = true
    /// The navigator's count when the app last left, so a route opened since is known.
    private var routesBeforeBackground = 0

    init(defaults: UserDefaults = .standard, opening: Duration = DS.Motion.appOpening) {
        self.defaults = defaults
        self.opening = opening
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

    /// The app is active. Opens De verificat when something new waits, no route came with the
    /// app and nothing is open over the tabs. Returns whether it did.
    ///
    /// A route asked for while the app was away wins at once. Otherwise it waits for one to
    /// come with the opening (a tapped reminder or link reaches the app while iOS brings it
    /// onto the screen) and gives way the moment one does; nothing tells when none will, so it
    /// waits no longer than the opening itself (`DS.Motion.appOpening`). A wait cut short (the
    /// app went inactive again, for Face ID) leaves it for the next time.
    @discardableResult
    func didBecomeActive(waiting: () -> [InboxItem], navigator: AppNavigator, isBusy: () -> Bool) async -> Bool {
        guard cameFromBackground else { return false }
        var routeOpened = navigator.openCount != routesBeforeBackground || navigator.pendingRoute != nil
        if !routeOpened { routeOpened = await navigator.routeArrives(within: opening) }
        guard !Task.isCancelled else { return false }
        cameFromBackground = false
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
