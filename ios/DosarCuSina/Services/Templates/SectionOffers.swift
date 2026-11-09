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
    /// "Alte secțiuni gata făcute": everything else that can be added on its own.
    public var others: [CategoryTemplate]

    public init(_ templates: [CategoryTemplate]) {
        let offered = templates
            .filter { !$0.behavior.addedOnlyUnderParent }
            .sorted { ($0.homeOrder, $0.createdAt) < ($1.homeOrder, $1.createdAt) }
        shortlist = offered
            .filter { $0.behavior.shortlistOrder != nil }
            .sorted { ($0.behavior.shortlistOrder ?? 0, $0.homeOrder) < ($1.behavior.shortlistOrder ?? 0, $1.homeOrder) }
        others = offered.filter { $0.behavior.shortlistOrder == nil }
    }

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
