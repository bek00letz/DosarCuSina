import Foundation
import SwiftData

/// What "Adaugă o secțiune" offers, read from the categories themselves: the ones most
/// households start with, in the order they declare (`CategoryBehavior.shortlistOrder`),
/// then every other category in the binder's order. A category whose sections are added
/// only under another one (a tenancy) isn't offered on its own. Each option reads as one
/// thing ("Mașină"), from the category's `offerTitle`, else its name. No screen names a
/// built-in, so a category of the person's own is listed like any other.
public struct SectionOffers {
    /// "Cele mai des folosite".
    public var shortlist: [CategoryTemplate]
    /// "Alte categorii": everything else that can be added on its own.
    public var others: [CategoryTemplate]

    /// Where a category is offered.
    public enum Group: Hashable, Sendable {
        case shortlist
        case others
    }

    public init(_ templates: [CategoryTemplate]) {
        let offered = CategoryTemplate.oncePerKey(templates)
            .filter { Self.group(of: $0.behavior) != nil }
            .sorted { ($0.homeOrder, $0.createdAt) < ($1.homeOrder, $1.createdAt) }
        shortlist = offered
            .filter { Self.group(of: $0.behavior) == .shortlist }
            .sorted { ($0.behavior.shortlistOrder ?? 0, $0.homeOrder) < ($1.behavior.shortlistOrder ?? 0, $1.homeOrder) }
        others = offered.filter { Self.group(of: $0.behavior) == .others }
    }

    /// The one rule for where a category is offered, from what it declares: among the ones most
    /// households start with when it has a place there (`shortlistOrder`), else with the others;
    /// nil when its sections are only added under another section (a tenancy, from its home).
    public static func group(of behavior: CategoryBehavior) -> Group? {
        guard !behavior.addedOnlyUnderParent else { return nil }
        return behavior.shortlistOrder == nil ? .others : .shortlist
    }

    /// Every category that can be added on its own, in the order it is offered: the shortlist,
    /// then the others. The binder's add box names from it (`BinderLayout.addBoxNames`).
    public var inOrder: [CategoryTemplate] { shortlist + others }

    /// The option's title: one thing, not the category ("Mașină", not "Mașini").
    public static func title(for template: CategoryTemplate) -> String {
        template.behavior.offerTitle(name: template.name)
    }
}

extension TemplateStore {
    /// What "Adaugă o secțiune" offers now.
    public func sectionOffers() throws -> SectionOffers {
        SectionOffers(try all())
    }
}
