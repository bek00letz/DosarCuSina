import Foundation
import Observation

/// One box on the Dosar grid.
enum BinderBoxID: Hashable, Sendable {
    /// A top-level asset: the car, the flat, PawPaw.
    case asset(UUID)
    /// A box that gathers one category: Acte, Garanții, Abonamente.
    case category(String)
    /// People and firms.
    case agenda

    /// How the box is written in the saved order.
    var storageKey: String {
        switch self {
        case .asset(let id): "asset:\(id.uuidString.lowercased())"
        case .category(let key): "category:\(key)"
        case .agenda: "agenda"
        }
    }

    init?(storageKey: String) {
        if storageKey == "agenda" {
            self = .agenda
        } else if storageKey.hasPrefix("asset:"), let id = UUID(uuidString: String(storageKey.dropFirst(6))) {
            self = .asset(id)
        } else if storageKey.hasPrefix("category:") {
            let key = String(storageKey.dropFirst(9))
            guard !key.isEmpty else { return nil }
            self = .category(key)
        } else {
            return nil
        }
    }

    /// Where tapping the box goes.
    var route: AppRoute {
        switch self {
        case .asset(let id): .asset(id)
        case .category(let key): .category(key)
        case .agenda: .agenda
        }
    }
}

/// Which boxes the Dosar grid shows and in what order. Pure, so it is tested.
///
/// What each category gets is its own data (`CategoryBehavior.box`), never its key:
/// - a category with many small records (Acte, Garanții, Abonamente) gets one box;
/// - every other category on the home screen gets one box per top-level asset;
/// - a category that lives inside another (tenancies in a home, people in Acte) gets
///   none. Anything filed under another asset lives inside its parent.
/// - Agenda comes last. The order follows the categories' home order until the
///   person rearranges the boxes; then their order wins and new boxes slot in
///   next to their neighbours.
enum BinderLayout {
    struct TemplateInfo: Hashable, Sendable {
        var key: String
        var homeOrder: Int
        var isOnHome: Bool
        var box: CategoryBehavior.Box = .perSection
    }

    struct AssetInfo: Hashable, Sendable {
        var id: UUID
        var templateKey: String
        var isTopLevel: Bool
        var createdAt: Date
    }

    static func defaultOrder(templates: [TemplateInfo], assets: [AssetInfo]) -> [BinderBoxID] {
        var result: [BinderBoxID] = []
        let boxes = Dictionary(templates.map { ($0.key, $0.box) }, uniquingKeysWith: { first, _ in first })
        let topLevel = assets.filter(\.isTopLevel).sorted { $0.createdAt < $1.createdAt }
        for template in templates.sorted(by: { $0.homeOrder < $1.homeOrder }) where template.isOnHome {
            switch template.box {
            case .wholeCategory: result.append(.category(template.key))
            case .perSection: result += topLevel.filter { $0.templateKey == template.key }.map { .asset($0.id) }
            case .insideOther: break
            }
        }
        // An asset whose category isn't installed still shows, as a standard box.
        result += topLevel.filter { boxes[$0.templateKey] == nil }.map { .asset($0.id) }
        result.append(.agenda)
        return result
    }

    /// The person's saved order applied to the boxes that exist now: boxes that are
    /// gone drop out, and new boxes go right after the box that precedes them by default.
    static func merge(saved: [BinderBoxID], defaults: [BinderBoxID]) -> [BinderBoxID] {
        guard !saved.isEmpty else { return defaults }
        let existing = Set(defaults)
        var seen = Set<BinderBoxID>()
        var result = saved.filter { existing.contains($0) && seen.insert($0).inserted }
        for (index, id) in defaults.enumerated() where !result.contains(id) {
            let anchor = defaults[..<index].last { result.contains($0) }
            if let anchor, let position = result.firstIndex(of: anchor) {
                result.insert(id, at: position + 1)
            } else {
                result.insert(id, at: 0)
            }
        }
        return result
    }

    /// Moves `id` into the place of `target` (what dragging over a box does).
    static func move(_ id: BinderBoxID, onto target: BinderBoxID, in order: [BinderBoxID]) -> [BinderBoxID] {
        guard id != target, let from = order.firstIndex(of: id), let to = order.firstIndex(of: target) else { return order }
        var result = order
        result.remove(at: from)
        result.insert(id, at: to)
        return result
    }

    /// Moves `id` one or more places earlier (negative) or later (positive).
    static func move(_ id: BinderBoxID, by offset: Int, in order: [BinderBoxID]) -> [BinderBoxID] {
        guard let from = order.firstIndex(of: id) else { return order }
        let to = min(max(from + offset, 0), order.count - 1)
        guard to != from else { return order }
        var result = order
        result.remove(at: from)
        result.insert(id, at: to)
        return result
    }
}

/// The person's box order, kept on this device. Only the order is stored; which
/// boxes exist always comes from the data.
@MainActor
@Observable
final class BinderLayoutStore {
    static let shared = BinderLayoutStore()

    private static let key = "binder.boxOrder"

    private(set) var saved: [BinderBoxID]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.stringArray(forKey: Self.key) ?? []
        saved = raw.compactMap(BinderBoxID.init(storageKey:))
    }

    func order(defaults boxes: [BinderBoxID]) -> [BinderBoxID] {
        BinderLayout.merge(saved: saved, defaults: boxes)
    }

    /// Replaces the order in memory (while dragging); call `persist()` when done.
    func update(_ order: [BinderBoxID]) {
        saved = order
    }

    func persist() {
        defaults.set(saved.map(\.storageKey), forKey: Self.key)
    }

    func reset() {
        saved = []
        defaults.removeObject(forKey: Self.key)
    }
}
