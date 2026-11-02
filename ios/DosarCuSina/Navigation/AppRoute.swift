import Foundation
import Observation

/// Every place the app can be opened to. Notifications, widgets, Spotlight,
/// App Intents and in-app links all speak this one type.
public enum AppRoute: Hashable, Sendable, Codable {
    /// The Dosar tab: the grid of section boxes.
    case home
    /// The Urmează tab: what comes up next.
    case upcoming
    /// The Caută tab.
    case search
    /// A section page for one asset (VW Golf, Apartament, PawPaw).
    case asset(UUID)
    /// Logging a visit (service, repair, check-up) on an asset.
    case addVisit(UUID)
    /// The Agenda box: people and firms.
    case obligation(UUID)
    case historyEntry(UUID)
    case provider(UUID)
    case document(UUID)
    case agenda
    /// A box that groups a category (Acte, Garanții, Abonamente), by `CategoryTemplate.key`.
    case category(String)
    /// The Adaugă tab: scan or add something.
    case intake
    case settings(SettingsSection?)
}

public enum SettingsSection: String, Hashable, Sendable, Codable, CaseIterable {
    case notifications
    case privacy
    case categories
    case backup
    case examples
    case about
}

/// `dosarcusina://` links, built and parsed in one place.
///
/// - `dosarcusina://home`, `dosarcusina://upcoming` (also `radar`, from earlier builds),
///   `dosarcusina://search`, `dosarcusina://intake`, `dosarcusina://agenda`
/// - `dosarcusina://asset/<uuid>`, `dosarcusina://visit/<asset uuid>`, `dosarcusina://obligation/<uuid>`, `dosarcusina://history/<uuid>`,
///   `dosarcusina://provider/<uuid>`, `dosarcusina://document/<uuid>`
/// - `dosarcusina://category/<key>`
/// - `dosarcusina://settings` or `dosarcusina://settings/<section>`
public enum DeepLink {
    public static let scheme = "dosarcusina"

    public static func url(for route: AppRoute) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        switch route {
        case .home: components.host = "home"
        case .upcoming: components.host = "upcoming"
        case .search: components.host = "search"
        case .agenda: components.host = "agenda"
        case .intake: components.host = "intake"
        case .addVisit(let id):
            components.host = "visit"
            components.path = "/" + id.uuidString.lowercased()
        case .asset(let id):
            components.host = "asset"
            components.path = "/" + id.uuidString.lowercased()
        case .obligation(let id):
            components.host = "obligation"
            components.path = "/" + id.uuidString.lowercased()
        case .historyEntry(let id):
            components.host = "history"
            components.path = "/" + id.uuidString.lowercased()
        case .provider(let id):
            components.host = "provider"
            components.path = "/" + id.uuidString.lowercased()
        case .document(let id):
            components.host = "document"
            components.path = "/" + id.uuidString.lowercased()
        case .category(let key):
            components.host = "category"
            components.path = "/" + key
        case .settings(let section):
            components.host = "settings"
            if let section { components.path = "/" + section.rawValue }
        }
        return components.url ?? URL(string: "\(scheme)://home")!
    }

    public static func route(from url: URL) -> AppRoute? {
        guard url.scheme?.lowercased() == scheme, let host = url.host()?.lowercased() else { return nil }
        let argument = url.pathComponents.dropFirst().first
        switch host {
        case "home": return .home
        case "upcoming", "radar": return .upcoming
        case "search": return .search
        case "agenda": return .agenda
        case "intake": return .intake
        case "visit": return argument.flatMap(UUID.init(uuidString:)).map(AppRoute.addVisit)
        case "asset": return argument.flatMap(UUID.init(uuidString:)).map(AppRoute.asset)
        case "obligation": return argument.flatMap(UUID.init(uuidString:)).map(AppRoute.obligation)
        case "history": return argument.flatMap(UUID.init(uuidString:)).map(AppRoute.historyEntry)
        case "provider": return argument.flatMap(UUID.init(uuidString:)).map(AppRoute.provider)
        case "document": return argument.flatMap(UUID.init(uuidString:)).map(AppRoute.document)
        case "category": return argument.map(AppRoute.category)
        case "settings": return .settings(argument.flatMap(SettingsSection.init(rawValue:)))
        default: return nil
        }
    }
}

/// Holds a route that arrived from outside the UI (a notification tap, a
/// widget, a URL) until the screen hierarchy consumes it.
@MainActor
@Observable
public final class AppNavigator {
    public static let shared = AppNavigator()

    public private(set) var pendingRoute: AppRoute?
    /// A `.dosar` file opened from Files, Mail or AirDrop, waiting for the import screen.
    public private(set) var pendingArchiveURL: URL?

    public init() {}

    public func open(_ route: AppRoute) {
        pendingRoute = route
    }

    /// Handles a deep link or an opened `.dosar` file. Returns false for anything else.
    @discardableResult
    public func open(_ url: URL) -> Bool {
        if url.isFileURL, url.pathExtension.lowercased() == "dosar" {
            pendingArchiveURL = url
            open(.settings(.backup))
            return true
        }
        guard let route = DeepLink.route(from: url) else { return false }
        open(route)
        return true
    }

    /// Returns the pending archive once and clears it.
    public func consumeArchiveURL() -> URL? {
        defer { pendingArchiveURL = nil }
        return pendingArchiveURL
    }

    /// Returns the pending route once and clears it.
    public func consume() -> AppRoute? {
        defer { pendingRoute = nil }
        return pendingRoute
    }
}
