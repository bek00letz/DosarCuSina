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
    /// A new document for a household member: photo first, or typed in.
    case addPersonalDocument(holderID: UUID)

    var id: String {
        switch self {
        case .settings(let section): "settings.\(section?.rawValue ?? "")"
        case .addVisit(let id): "visit.\(id.uuidString)"
        case .addSection(let request): "section.\(request.parentID?.uuidString ?? "")\(request.templateKey ?? "")"
        case .addPersonalDocument(let holderID): "personalDocument.\(holderID.uuidString)"
        }
    }
}

/// Where a route lands: a tab, the screens pushed on it, and maybe a sheet on top.
struct ShellRoutePlan: Equatable, Sendable {
    var tab: AppTab
    var path: [AppRoute]
    var sheet: ShellSheet?
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
    var sheet: ShellSheet?

    @ObservationIgnored private var pendingSheet: Task<Void, Never>?

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
    /// screen first so sheets never stack.
    func present(_ newSheet: ShellSheet?) {
        pendingSheet?.cancel()
        if sheet == nil || newSheet == nil {
            sheet = newSheet
            return
        }
        sheet = nil
        pendingSheet = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self?.sheet = newSheet
        }
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
