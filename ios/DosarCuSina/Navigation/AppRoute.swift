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
    /// A situation's checklist: a trip, selling the car, a claim (`ReadinessSituation`).
    case readiness(ReadinessRoute)
}

public enum SettingsSection: String, Hashable, Sendable, Codable, CaseIterable {
    case notifications
    case privacy
    case categories
    case backup
    case examples
    /// The repair list: data an earlier version saved wrongly, waiting for an OK.
    case repairs
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
/// - `dosarcusina://ready/trip`, `dosarcusina://ready/trip/<member uuid>`,
///   `dosarcusina://ready/sale/<asset uuid>`, `dosarcusina://ready/claim/<asset uuid>`
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
        case .readiness(let readiness):
            components.host = "ready"
            components.path = "/" + readiness.situation.rawValue + (readiness.assetID.map { "/" + $0.uuidString.lowercased() } ?? "")
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
        case "ready": return readiness(situation: argument, id: url.pathComponents.dropFirst(2).first)
        default: return nil
        }
    }
}

extension DeepLink {
    /// `ready/<situation>[/<uuid>]`: a trip may name a member; a sale or a claim must name its section.
    private static func readiness(situation: String?, id argument: String?) -> AppRoute? {
        let id = argument.flatMap(UUID.init(uuidString:))
        switch situation.flatMap(ReadinessSituation.init(rawValue:)) {
        case .trip: return .readiness(.trip(holderID: id))
        case .sale: return id.map { .readiness(.sale(assetID: $0)) }
        case .claim: return id.map { .readiness(.claim(assetID: $0)) }
        case nil: return nil
        }
    }
}

/// Holds a route that arrived from outside the UI (a notification tap, a
/// widget, a URL) until the screen hierarchy consumes it. While the app lock is
/// closed nothing is handed out: links and opened files wait until unlocking.
@MainActor
@Observable
public final class AppNavigator {
    public static let shared = AppNavigator()

    public private(set) var pendingRoute: AppRoute?
    /// A `.dosar` file opened from Files, Mail or AirDrop, waiting for the import screen.
    public private(set) var pendingArchiveURL: URL?

    @ObservationIgnored private let isAppLocked: @MainActor () -> Bool

    public init(isAppLocked: @escaping @MainActor () -> Bool = { BiometricVaultManager.shared.isAppLocked }) {
        self.isAppLocked = isAppLocked
    }

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

    /// Opens a result tapped in the iPhone's search, by the identifier it was indexed
    /// with (`SpotlightEntry.identifier`). Like any link, it waits while the app is locked.
    @discardableResult
    public func open(spotlightIdentifier identifier: String) -> Bool {
        guard let route = SpotlightEntry.route(forIdentifier: identifier) else { return false }
        open(route)
        return true
    }

    /// Returns the pending archive once and clears it. While the app is locked
    /// it stays pending and nothing is returned.
    public func consumeArchiveURL() -> URL? {
        guard !isAppLocked() else { return nil }
        defer { pendingArchiveURL = nil }
        return pendingArchiveURL
    }

    /// Returns the pending route once and clears it. While the app is locked it
    /// stays pending, so a link or a notification opens only after unlocking.
    public func consume() -> AppRoute? {
        guard !isAppLocked() else { return nil }
        defer { pendingRoute = nil }
        return pendingRoute
    }
}
