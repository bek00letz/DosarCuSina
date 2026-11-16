import SwiftUI
import SwiftData

// MARK: - The rule

/// Whether one pocket of a page has something in it.
enum PocketFill: Equatable, Sendable {
    case filled
    case empty
    /// Not offered on this page at all: a pocket of sections that have boxes of their own
    /// (plants) on a home, while the household keeps none.
    case notOffered
}

/// Something a page can add to one of its pockets. The one list behind both a pocket's own
/// button and the page's "Adaugă…" menu, so they read and do the same; each opens its own
/// flow in place, over the page (`SectionPocketList`).
enum PocketAddition: Hashable, Identifiable, Sendable {
    /// A deadline, in the one deadline form (`DeadlineForm`): its category's usual ones or one of the person's own.
    case deadline
    /// A section filed under this one (a tenant, a product, a subscription, a plant).
    case child(SectionPocket, templateKey: String)
    /// A household member's own document (photo first, or typed in).
    case personalDocument
    /// A photo of a paper for this section, through capture (`photoFirstCapture`). Beside a
    /// person's own documents it is named apart from them.
    case paper(besidePersonal: Bool)
    /// A visit, a repair or a job, in the category's own words (`VisitWording.title`).
    case visit(title: String)
    /// Someone who looks after it.
    case person
    /// A row of the person's own under Date importante.
    case keyFact

    var id: String {
        switch self {
        case .deadline: "deadline"
        case .child(let pocket, let key): "child.\(pocket.rawValue).\(key)"
        case .personalDocument: "personalDocument"
        case .paper: "paper"
        case .visit: "visit"
        case .person: "person"
        case .keyFact: "keyFact"
        }
    }

    /// The pocket it adds to, named under it in the menu.
    var pocket: SectionPocket {
        switch self {
        case .deadline: .upcoming
        case .child(let pocket, _): pocket
        case .personalDocument, .paper: .documents
        case .visit: .history
        case .person: .people
        case .keyFact: .keyFacts
        }
    }

    var title: String {
        switch self {
        case .deadline: String(localized: "Adaugă un termen", comment: "Adds a deadline to a section, from its Urmează pocket or its add menu.")
        case .child(let pocket, _): Self.childTitle(pocket)
        case .personalDocument: String(localized: "Adaugă un act", comment: "Adds a document for a household member.")
        case .paper(let besidePersonal):
            besidePersonal
                ? String(localized: "Scanează un document", comment: "Adds a photo of another paper on a person's page, beside their own documents.")
                : String(localized: "Adaugă un act", comment: "Adds a photo of a paper to a section, from its Acte pocket or its add menu.")
        case .visit(let title): title
        case .person: String(localized: "Adaugă o persoană", comment: "Adds someone who looks after a section.")
        case .keyFact: String(localized: "Adaugă un rând", comment: "Adds a row of one's own under Date importante.")
        }
    }

    private static func childTitle(_ pocket: SectionPocket) -> String {
        switch pocket {
        case .tenants: String(localized: "Adaugă un chiriaș", comment: "Button in the Chiriași pocket.")
        case .products: String(localized: "Adaugă un produs", comment: "Button in the Produse pocket.")
        case .plants: String(localized: "Adaugă o plantă", comment: "Button in the Plante pocket of a home's page.")
        default: String(localized: "Adaugă un abonament", comment: "Button in the Abonamente pocket.")
        }
    }

    var systemImage: String {
        switch self {
        case .deadline: "calendar.badge.plus"
        case .child: "plus"
        case .personalDocument: "person.text.rectangle"
        case .paper: "doc.viewfinder"
        case .visit: "wrench.and.screwdriver"
        case .person: "person.badge.plus"
        case .keyFact: "list.bullet.rectangle"
        }
    }
}

/// What a page draws of its pockets, by one rule for every pocket: a pocket with something
/// in it shows in its usual place, in the one global order; an empty one isn't drawn as a
/// card but folds into the page's one "Adaugă…" menu, by what it adds; Bani, which adds
/// nothing itself, shows only once there is money.
struct SectionPageLayout: Equatable, Sendable {
    var shown: [SectionPocket]
    var additions: [PocketAddition]

    /// On: empty pockets fold into "Adaugă…". Off: every pocket the category lists shows,
    /// empty ones with their sentence, as before; kept as the way back until the owner has
    /// used the folded page.
    static let foldsEmptyPockets = true

    /// - Parameters:
    ///   - revealed: pockets shown although empty, because the person is adding to them right
    ///     there (a first row under Date importante).
    static func make(
        pockets: [SectionPocket],
        revealed: Set<SectionPocket> = [],
        folds: Bool = foldsEmptyPockets,
        fill: (SectionPocket) -> PocketFill,
        addition: (SectionPocket) -> PocketAddition?
    ) -> SectionPageLayout {
        var layout = SectionPageLayout(shown: [], additions: [])
        for pocket in SectionPocket.ordered(pockets) {
            switch fill(pocket) {
            case .filled:
                layout.shown.append(pocket)
            case .empty:
                if !folds || revealed.contains(pocket) {
                    layout.shown.append(pocket)
                } else if let addition = addition(pocket) {
                    layout.additions.append(addition)
                }
            case .notOffered:
                break
            }
        }
        return layout
    }
}

// MARK: - What each pocket holds

/// What a section's pockets hold, read once for the page: the one source for whether a pocket
/// shows and for what the pocket lists.
@MainActor
struct PocketContents {
    let asset: Asset
    let definition: TemplateDefinition
    /// Every category, for what the child pockets gather and what a document is.
    let templates: [CategoryTemplate]
    /// Who looks after it: linked to it, or worked on it (`ProviderDirectory.providers(for:)`).
    let providers: [Provider]

    private var isHolder: Bool { definition.behavior.role == .holder }

    func fill(_ pocket: SectionPocket) -> PocketFill {
        switch pocket {
        case .upcoming:
            return UpcomingPocket.listed(asset).isEmpty ? .empty : .filled
        case .tenants, .products, .subscriptions, .plants:
            let children = ChildrenPocket.contents(of: asset, pocket: pocket, templates: templates)
            if !children.children.isEmpty { return .filled }
            return children.isOffered ? .empty : .notOffered
        case .documents:
            return SectionPapers.isEmpty(asset, templates: templates) ? .empty : .filled
        case .history:
            return (asset.history ?? []).isEmpty ? .empty : .filled
        case .people:
            return providers.isEmpty ? .empty : .filled
        case .money:
            return MoneyPocket.Facts.make(asset: asset, definition: definition).isEmpty ? .empty : .filled
        case .keyFacts:
            return AssetFacts.factRows(asset.values, customFacts: asset.customFacts, template: definition).isEmpty ? .empty : .filled
        }
    }

    /// What the pocket's own button adds, which is also what the page's menu offers for it.
    func addition(_ pocket: SectionPocket) -> PocketAddition? {
        switch pocket {
        case .upcoming:
            return .deadline
        case .tenants, .products, .subscriptions, .plants:
            guard let key = ChildrenPocket.contents(of: asset, pocket: pocket, templates: templates).childKey else { return nil }
            return .child(pocket, templateKey: key)
        case .documents:
            return isHolder ? .personalDocument : .paper(besidePersonal: false)
        case .history:
            return .visit(title: definition.behavior.visitWording.title)
        case .people:
            return .person
        case .money:
            return nil
        case .keyFacts:
            return .keyFact
        }
    }

    func layout(pockets: [SectionPocket], revealed: Set<SectionPocket> = [], folds: Bool = SectionPageLayout.foldsEmptyPockets) -> SectionPageLayout {
        SectionPageLayout.make(pockets: pockets, revealed: revealed, folds: folds, fill: { fill($0) }, addition: { addition($0) })
    }
}

// MARK: - A section's papers

extension Attachment {
    /// A paper filed with a record (a visit's invoice, a bill, an inspection's report) is that
    /// record's: it opens from the record in Istoric, not again in Acte. A paper valid until a
    /// day (a policy or a document renewed with "Am rezolvat") stands for the section too, so
    /// it stays in Acte as well.
    var isItsRecordsPaper: Bool {
        historyEntry != nil && validUntil == nil
    }
}

/// The papers a section's Acte lists, by one rule for the pocket, "Vezi tot" and its counts:
/// a person's own documents, then the section's papers that aren't a record's.
@MainActor
enum SectionPapers {
    /// The household member's own documents filed under `asset`, by category.
    static func personal(_ asset: Asset, templates: [CategoryTemplate]) -> [Asset] {
        let documentKeys = Set(templates.filter { $0.behavior.role == .personalDocument }.map(\.key))
        return (asset.children ?? []).filter { documentKeys.contains($0.templateKey) }
    }

    /// The section's papers in use, newest first, without the records' own.
    static func listed(_ asset: Asset) -> [Attachment] {
        all(asset).filter { !$0.isArchived }
    }

    /// The ones kept for reference ("Arhivate"), newest first, without the records' own.
    static func archived(_ asset: Asset) -> [Attachment] {
        all(asset).filter(\.isArchived)
    }

    static func isEmpty(_ asset: Asset, templates: [CategoryTemplate]) -> Bool {
        personal(asset, templates: templates).isEmpty && all(asset).isEmpty
    }

    private static func all(_ asset: Asset) -> [Attachment] {
        (asset.attachments ?? []).filter { !$0.isItsRecordsPaper }.sorted { $0.createdAt > $1.createdAt }
    }
}
