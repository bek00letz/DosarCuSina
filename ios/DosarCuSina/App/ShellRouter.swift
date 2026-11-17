import SwiftUI
import Observation

/// The four tabs of the app.
enum AppTab: String, Hashable, CaseIterable, Sendable {
    case dosar
    case upcoming
    case add
    case search
}

/// What adding a section starts from: the whole catalog, or one category under a parent
/// (a tenant under a home, a document under a person).
struct AddSectionRequest: Hashable, Sendable {
    /// The asset the new one is filed under.
    var parentID: UUID?
    /// Skips the catalog and starts with this category.
    var templateKey: String?

    static let topLevel = AddSectionRequest()
}

/// Screens the shell presents as sheets over whatever tab is showing.
enum ShellSheet: Identifiable, Hashable, Sendable {
    case settings(SettingsSection?)
    case addVisit(UUID)
    case addSection(AddSectionRequest)
    /// A new document for a household member: photo first, or typed in. Without a holder (the
    /// Acte box), the photo names them and "Scriu eu" asks whose it is.
    case addPersonalDocument(holderID: UUID?)

    var id: String {
        switch self {
        case .settings(let section): "settings.\(section?.rawValue ?? "")"
        case .addVisit(let id): "visit.\(id.uuidString)"
        case .addSection(let request): "section.\(request.parentID?.uuidString ?? "")\(request.templateKey ?? "")"
        case .addPersonalDocument(let holderID): "personalDocument.\(holderID?.uuidString ?? "")"
        }
    }

    /// The section the sheet writes into, behind its lock: a visit into its section, a section
    /// or a document under its parent or holder. A new top-level section or a document with no
    /// holder yet reveals nothing, so it opens as it is.
    var lock: RouteLock {
        switch self {
        case .settings: .open
        case .addVisit(let id): .section(id)
        case .addSection(let request): request.parentID.map(RouteLock.section) ?? .open
        case .addPersonalDocument(let holderID): holderID.map(RouteLock.section) ?? .open
        }
    }
}

/// What a route or a sheet shows or writes, as far as the section locks go. Every route
/// (`AppRoute.lock`) and every sheet (`ShellSheet.lock`) declares it in a switch of its own, so a
/// new one can't leave it out, and the shell draws each through `RouteLockGate`, wherever it
/// came from: a tap, a reminder, a widget, a `dosarcusina://` link, a search result.
enum RouteLock: Hashable, Sendable {
    /// Nothing of one section: a tab, Settings, the people and firms.
    case open
    /// Shows or writes into this section: drawn only while its category is open, by the one answer
    /// (`Asset.isSensitive(template:)`), and a locked state with Face ID until then.
    case section(UUID)
    /// One record of a section, or what several sections hold: its screen finds the section by the
    /// same answer and draws a locked state of its own that names nothing of it (a deadline's page
    /// keeps its due day, a checklist says it reads protected data, a firm's page leaves the
    /// locked sections out).
    case drawnByItsScreen
}

extension AppRoute {
    /// The lock the route's screen opens behind (`RouteLock`).
    var lock: RouteLock {
        switch self {
        case .home, .upcoming, .search, .intake, .settings, .agenda: .open
        case .asset(let id), .addVisit(let id): .section(id)
        case .obligation, .historyEntry, .document, .provider, .category, .readiness: .drawnByItsScreen
        }
    }
}

/// Where a route lands: a tab, the screens pushed on it, and maybe a sheet on top.
struct ShellRoutePlan: Equatable, Sendable {
    var tab: AppTab
    var path: [AppRoute]
    var sheet: ShellSheet?

    /// Every lock the plan opens behind, the pushed screens' and the sheet's, in order: what
    /// the shell checks before it draws them.
    var locks: [RouteLock] { path.map(\.lock) + (sheet.map { [$0.lock] } ?? []) }
}

/// The one mapping from an `AppRoute` (a notification, a widget, a `dosarcusina://`
/// link, a search result) to the place it opens. Pure, so it is tested.
enum ShellRouting {
    static func plan(for route: AppRoute) -> ShellRoutePlan {
        switch route {
        case .home:
            return ShellRoutePlan(tab: .dosar, path: [])
        case .upcoming:
            return ShellRoutePlan(tab: .upcoming, path: [])
        case .search:
            return ShellRoutePlan(tab: .search, path: [])
        case .intake:
            return ShellRoutePlan(tab: .add, path: [])
        case .asset:
            return ShellRoutePlan(tab: .dosar, path: [route])
        case .addVisit(let id):
            return ShellRoutePlan(tab: .dosar, path: [.asset(id)], sheet: .addVisit(id))
        case .obligation:
            return ShellRoutePlan(tab: .upcoming, path: [route])
        case .historyEntry, .document, .category:
            return ShellRoutePlan(tab: .dosar, path: [route])
        case .agenda:
            return ShellRoutePlan(tab: .dosar, path: [.agenda])
        case .provider:
            return ShellRoutePlan(tab: .dosar, path: [.agenda, route])
        case .settings(let section):
            return ShellRoutePlan(tab: .dosar, path: [], sheet: .settings(section))
        case .readiness(let readiness):
            // Over the section it belongs to; a trip for the household opens over Urmează.
            if let id = readiness.assetID {
                return ShellRoutePlan(tab: .dosar, path: [.asset(id), route])
            }
            return ShellRoutePlan(tab: .upcoming, path: [route])
        }
    }
}

/// The shell's one sheet, and the one waiting for it to finish closing, so sheets never
/// stack and the next opens as soon as the last is gone: when its dismissal completes,
/// not after a guessed pause. Pure, so it is tested.
struct ShellSheetQueue: Equatable, Sendable {
    /// What the shell asks to show; nil while nothing should be up (or the last is closing).
    private(set) var shown: ShellSheet?
    /// Opens once the sheet on screen has finished closing.
    private(set) var waiting: ShellSheet?
    /// A sheet is on screen, or still on its way off it.
    private(set) var isOnScreen = false

    /// Something is up, closing, or about to open.
    var isBusy: Bool { shown != nil || waiting != nil || isOnScreen }

    /// Shows `next` (nil closes). Over a sheet on screen it closes that one first and waits.
    mutating func present(_ next: ShellSheet?) {
        guard isOnScreen else {
            // Nothing to wait for: it opens (or closes) right away.
            shown = next
            waiting = nil
            return
        }
        if next == shown {
            // Already up (or nothing asked while one closes): forget anything waiting.
            waiting = nil
            return
        }
        waiting = next
        shown = nil
    }

    /// The sheet came on screen.
    mutating func didAppear() {
        isOnScreen = true
    }

    /// The sheet finished closing, however it closed: the waiting one opens now.
    mutating func didDismiss() {
        isOnScreen = false
        if let waiting {
            shown = waiting
            self.waiting = nil
        }
    }
}

/// Owns the selected tab, each tab's navigation path and the shell's sheet.
/// Every route, from inside or outside the app, goes through `open(_:)`.
@MainActor
@Observable
final class ShellRouter {
    var tab: AppTab = .dosar
    var dosarPath = NavigationPath()
    var upcomingPath = NavigationPath()
    var addPath = NavigationPath()
    var searchPath = NavigationPath()
    private var sheets = ShellSheetQueue()

    /// The sheet over the tabs. Closing it by hand (a swipe) writes nil here.
    var sheet: ShellSheet? {
        get { sheets.shown }
        set { present(newValue) }
    }

    /// A sheet is up, closing or about to open: nothing else should pop up over the tabs.
    var hasSheet: Bool { sheets.isBusy }

    /// Opens a route: switches tab, replaces that tab's path and presents a sheet if needed.
    func open(_ route: AppRoute) {
        let plan = ShellRouting.plan(for: route)
        tab = plan.tab
        var path = NavigationPath()
        for step in plan.path { path.append(step) }
        setPath(path, for: plan.tab)
        present(plan.sheet)
    }

    /// Presents a sheet (or closes the current one with nil), closing the one on
    /// screen first so sheets never stack; the new one opens once that has closed.
    func present(_ newSheet: ShellSheet?) {
        sheets.present(newSheet)
    }

    /// The shell's sheet came on screen.
    func sheetDidAppear() {
        sheets.didAppear()
    }

    /// The shell's sheet finished closing (its `onDismiss`).
    func sheetDidDismiss() {
        sheets.didDismiss()
    }

    /// Pushes a screen on the current tab.
    func push(_ route: AppRoute) {
        switch tab {
        case .dosar: dosarPath.append(route)
        case .upcoming: upcomingPath.append(route)
        case .add: addPath.append(route)
        case .search: searchPath.append(route)
        }
    }

    /// Selecting the tab that is already showing goes back to its first screen.
    func select(_ newTab: AppTab) {
        if newTab == tab {
            setPath(NavigationPath(), for: newTab)
        }
        tab = newTab
    }

    private func setPath(_ path: NavigationPath, for tab: AppTab) {
        switch tab {
        case .dosar: dosarPath = path
        case .upcoming: upcomingPath = path
        case .add: addPath = path
        case .search: searchPath = path
        }
    }
}
