import Foundation
import Observation
import SwiftData

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
/// - a category with many small records (Acte, Garanții, Abonamente) gets one box, once it
///   holds something (`holds`: a person's documents' box holds the people too);
/// - every other category on the home screen gets one box per top-level asset, or, when its
///   sections are grouped (`CategoryTemplate.groupsSections`: the person's choice, else the
///   catalog's, as for plants), one box for all of them, wherever they are filed, once it has any;
/// - a category that lives inside another (tenancies in a home, people in Acte) gets
///   none. Anything filed under another asset lives inside its parent.
/// - Agenda comes last, once it holds someone.
/// - A category with nothing yet has no box: it is folded into the add box, which names it
///   (`addBoxNames`), so the binder still shows what it can hold. The order follows the
///   categories' home order until the person rearranges the boxes; then their order wins and
///   new boxes slot in next to their neighbours.
enum BinderLayout {
    struct TemplateInfo: Hashable, Sendable {
        var key: String
        var homeOrder: Int
        var isOnHome: Bool
        var box: CategoryBehavior.Box = .perSection
        /// Its sections share one box (`CategoryTemplate.groupsSections`).
        var groupsSections = false
        /// The part it plays (`CategoryBehavior.role`): a personal-documents box holds the people.
        var role: CategoryBehavior.Role?
        /// Its name, as the add box writes it ("Garanții").
        var name = ""
    }

    /// Whether `category`'s one box holds `asset`: its own sections, and, for the box of personal
    /// documents (Acte), the people they are filed under. The one rule the grid's boxes and their
    /// lines read.
    static func holds(_ category: TemplateInfo, assetOf assetCategory: TemplateInfo?, assetKey: String) -> Bool {
        assetKey == category.key || (category.role == .personalDocument && assetCategory?.role == .holder)
    }

    /// Whether a category has anything on the binder yet, by `holds`.
    static func holdsAnything(_ category: TemplateInfo, templates: [String: TemplateInfo], assets: [AssetInfo]) -> Bool {
        assets.contains { holds(category, assetOf: templates[$0.templateKey], assetKey: $0.templateKey) }
    }

    /// The most the add box names before it says there is more ("…").
    static let addBoxNameLimit = 4

    /// What the add box names: the categories on the binder that have no box yet, only those
    /// "Adaugă o secțiune" offers (`offered`, from `SectionOffers`): first the boxes folded into it
    /// (a whole category's: Acte, Garanții, Abonamente), where the binder would show them, then
    /// the rest in the order they are offered; at most `addBoxNameLimit`, and whether there are
    /// more. A category without a box of its own (tenants, people) is never named: its sections
    /// live inside another. Empty once everything has a box.
    static func addBoxNames(offered: [TemplateInfo], templates: [TemplateInfo], assets: [AssetInfo]) -> (names: [String], more: Bool) {
        let byKey = Dictionary(CategoryTemplate.oncePerKey(templates).map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let waiting = offered.filter { $0.isOnHome && $0.box != .insideOther && !holdsAnything($0, templates: byKey, assets: assets) }
        let folded = waiting.filter { $0.box == .wholeCategory }.sorted { $0.homeOrder < $1.homeOrder }
        let ordered = folded + waiting.filter { $0.box != .wholeCategory }
        return (ordered.prefix(addBoxNameLimit).map(\.name), ordered.count > addBoxNameLimit)
    }

    /// The add box's line under its title: „Acte, Garanții, Abonamente, Mașini…”; nil with nothing to name.
    static func addBoxLine(_ names: (names: [String], more: Bool)) -> String? {
        guard !names.names.isEmpty else { return nil }
        return names.names.joined(separator: ", ") + (names.more ? "…" : "")
    }

    struct AssetInfo: Hashable, Sendable {
        var id: UUID
        var templateKey: String
        var isTopLevel: Bool
        var createdAt: Date
    }

    static func defaultOrder(templates: [TemplateInfo], assets: [AssetInfo], hasContacts: Bool) -> [BinderBoxID] {
        var result: [BinderBoxID] = []
        let byKey = Dictionary(CategoryTemplate.oncePerKey(templates).map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let topLevel = assets.filter(\.isTopLevel).sorted { $0.createdAt < $1.createdAt }
        for template in templates.sorted(by: { $0.homeOrder < $1.homeOrder }) where template.isOnHome {
            switch template.box {
            case .wholeCategory:
                // Folded into the add box until it holds something.
                if holdsAnything(template, templates: byKey, assets: assets) { result.append(.category(template.key)) }
            case .perSection where template.groupsSections:
                if assets.contains(where: { $0.templateKey == template.key }) { result.append(.category(template.key)) }
            case .perSection: result += sectionBoxes(of: template.key, assets: topLevel)
            case .insideOther: break
            }
        }
        // An asset whose category isn't installed still shows, as a standard box.
        result += topLevel.filter { byKey[$0.templateKey] == nil }.map { .asset($0.id) }
        if hasContacts { result.append(.agenda) }
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

    /// The boxes a category's sections have when each has its own: the top-level ones, oldest first.
    static func sectionBoxes(of key: String, assets: [AssetInfo]) -> [BinderBoxID] {
        assets.filter { $0.isTopLevel && $0.templateKey == key }.sorted { $0.createdAt < $1.createdAt }.map { .asset($0.id) }
    }

    /// The saved order once a category's section boxes (`members`, in the order they show) are
    /// grouped into its one box, or that box is split into them again: the new box takes the
    /// place of the first of the old ones, so nothing else moves. An order that holds none of
    /// them stays as it is, and `merge` puts the new box where the defaults say.
    static func regrouped(_ saved: [BinderBoxID], category key: String, members: [BinderBoxID], grouped: Bool) -> [BinderBoxID] {
        let box = BinderBoxID.category(key)
        let sections = Set(members)
        var result: [BinderBoxID] = []
        if grouped {
            guard saved.contains(where: sections.contains) else { return saved }
            for id in saved where id != box {
                if !sections.contains(id) {
                    result.append(id)
                } else if !result.contains(box) {
                    result.append(box)
                }
            }
        } else {
            guard saved.contains(box) else { return saved }
            for id in saved where !sections.contains(id) {
                if id == box { result += members } else { result.append(id) }
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

    /// Groups a category's sections into one box, or gives each its box again, from wherever it
    /// is offered (a box's menu, Setări › Ecranul Dosar): the person's choice, kept on the
    /// category (`TemplateStore.setGrouping`), and this device's order kept around it, the one box
    /// standing where the first of its sections stood (`BinderLayout.regrouped`).
    func setGrouping(_ template: CategoryTemplate, _ grouping: BoxGrouping, assets: [Asset], context: ModelContext) throws {
        let members = BinderLayout.sectionBoxes(of: template.key, assets: assets.map(BinderLayout.AssetInfo.init))
        try TemplateStore(context: context).setGrouping(template, grouping)
        keepOrder(of: template.key, members: members, grouped: grouping == .grouped)
    }

    /// This device's order kept around a category whose grouping just changed: from here, or from
    /// a category of one's own's „O cutie pentru toate” in its edit sheet (`TemplateStore.editCustom`).
    /// `members` are its sections' boxes as they were before, in the order they showed.
    func keepOrder(of key: String, members: [BinderBoxID], grouped: Bool) {
        guard !saved.isEmpty else { return }
        saved = BinderLayout.regrouped(saved, category: key, members: members, grouped: grouped)
        persist()
    }

    func reset() {
        saved = []
        defaults.removeObject(forKey: Self.key)
    }
}
