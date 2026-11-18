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

/// One pocket of a page: one its category lists (`SectionPocket`), or the sections of a category
/// that belongs to the part this page plays and has no pocket of the catalog's (a category of
/// one's own that says "Ține de… O mașină", on every car's page), named after that category
/// (`CategoryBehavior.hasPocketOfItsOwn`). The page's one order: the listed pockets in theirs,
/// the categories' pockets right after the catalog's own pockets of sections filed under it
/// (tenants, products, subscriptions, plants), before Acte.
enum PagePocket: Hashable, Sendable {
    case listed(SectionPocket)
    /// A category's own pocket: its key, and its name, the pocket's title.
    case category(key: String, name: String)

    var title: String {
        switch self {
        case .listed(let pocket): pocket.title
        case .category(_, let name): name
        }
    }

    /// The listed pocket, if it is one.
    var listedPocket: SectionPocket? {
        if case .listed(let pocket) = self { return pocket }
        return nil
    }

    /// The pockets of a page, in the one order: `listed` (in the global order) with the
    /// categories' own pockets (`categories`, in their binder order) after the last pocket of
    /// sections filed under it.
    static func ordered(listed: [SectionPocket], categories: [PagePocket]) -> [PagePocket] {
        let pockets = SectionPocket.ordered(listed)
        let split = pockets.firstIndex { $0 > .plants } ?? pockets.endIndex
        return pockets[..<split].map(PagePocket.listed) + categories + pockets[split...].map(PagePocket.listed)
    }
}

/// Something a page can add to one of its pockets. The one list behind both a pocket's own
/// button and the page's "Adaugă…" menu, so they read and do the same; each opens its own
/// flow in place, over the page (`SectionPocketList`).
enum PocketAddition: Hashable, Identifiable, Sendable {
    /// A deadline, in the one deadline form (`DeadlineForm`): its category's usual ones or one of the person's own.
    case deadline
    /// A section filed under this one (a tenant, a product, a subscription, a plant, one of a
    /// category of one's own that belongs here).
    case child(PagePocket, templateKey: String)
    /// Any document of a household member's, photo first (`AddPersonalDocumentFlow` with
    /// `HolderDocumentFiling.captureDecides`): capture decides whether it is one of their own
    /// documents (`CaptureKindProfile.isPersonalDocument`: its own section, with reminders) or
    /// another paper kept on their page; „Scriu eu” types one of their own in by hand.
    case document
    /// A household member's own document (photo first, or typed in). Offered only by the
    /// two-button layout kept as the way back (`PocketAddition.offersOneDocumentButton`).
    case personalDocument
    /// A photo of a paper for this section, through capture (`photoFirstCapture`). Beside a
    /// person's own documents (the way back's second button) it is named apart from them.
    case paper(besidePersonal: Bool)
    /// A visit of the category's kind, in its words (`VisitShape.title`): a service, a job, a
    /// repair, a doctor's or a vet's visit.
    case visit(VisitKind)
    /// A dated note in Istoric, where the category takes notes instead of visits (a plant).
    case note
    /// Someone who looks after it.
    case person
    /// A row of the person's own under Date importante.
    case keyFact

    /// Each addition is its own identity: a page offers each at most once.
    var id: PocketAddition { self }

    /// The pocket it adds to, named under it in the menu.
    var pocket: PagePocket {
        switch self {
        case .deadline: .listed(.upcoming)
        case .child(let pocket, _): pocket
        case .document, .personalDocument, .paper: .listed(.documents)
        case .visit, .note: .listed(.history)
        case .person: .listed(.people)
        case .keyFact: .listed(.keyFacts)
        }
    }

    /// What the menu says under it: the pocket it goes in, unless its title names it already
    /// („Adaugă în „Anvelope””).
    var menuDetail: String? {
        if case .child(.category, _) = self { return nil }
        return pocket.title
    }

    /// On: a person's Acte has one button, „Adaugă un document”, and capture decides what the
    /// paper is (`document`). Off: the two buttons it replaced, „Adaugă un act” for one of their
    /// own documents and „Scanează un document” for another paper; kept as the way back until
    /// the owner has seen the one button on a phone.
    static let offersOneDocumentButton = true

    /// What Acte's own buttons add: a person any document of theirs, one button; any other
    /// section a photo of a paper. The first is what the page's menu offers for Acte
    /// (`PocketContents.addition`).
    static func documentButtons(isHolder: Bool, oneButton: Bool = offersOneDocumentButton) -> [PocketAddition] {
        guard isHolder else { return [.paper(besidePersonal: false)] }
        return oneButton ? [.document] : [.personalDocument, .paper(besidePersonal: true)]
    }

    // Its words and symbol are in `PocketWording.swift` (`title`, `systemImage`).
}

/// What a page draws of its pockets, by one rule for every pocket: a pocket with something
/// in it shows in its usual place, in the one global order; an empty one isn't drawn as a
/// card but folds into the page's one "Adaugă…" menu, by what it adds; Bani, which adds
/// nothing itself, shows only once there is money.
struct SectionPageLayout: Equatable, Sendable {
    var shown: [PagePocket]
    var additions: [PocketAddition]

    /// On: empty pockets fold into "Adaugă…". Off: every pocket the category lists shows,
    /// empty ones with their sentence, as before; kept as the way back until the owner has
    /// used the folded page.
    static let foldsEmptyPockets = true

    /// - Parameters:
    ///   - revealed: pockets shown although empty, because the person is adding to them right
    ///     there (a first row under Date importante).
    ///   - pockets: the page's pockets in its one order (`PagePocket.ordered`).
    static func make(
        pockets: [PagePocket],
        revealed: Set<PagePocket> = [],
        folds: Bool = foldsEmptyPockets,
        fill: (PagePocket) -> PocketFill,
        addition: (PagePocket) -> PocketAddition?
    ) -> SectionPageLayout {
        var layout = SectionPageLayout(shown: [], additions: [])
        for pocket in pockets {
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

extension PocketAddition {
    /// What Istoric adds, by the category's visit kind: its visit, a note (a plant), or nothing
    /// (a subscription, whose bills come with a photo). The one rule for the pocket's button and
    /// the page's menu.
    static func history(of behavior: CategoryBehavior) -> PocketAddition? {
        if behavior.visit.offersVisit { return .visit(behavior.visit) }
        return behavior.visit.addsNote ? .note : nil
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

    /// The categories whose sections belong to the part this page plays and show here in a pocket
    /// named after them (`CategoryBehavior.hasPocketOfItsOwn`: a category of one's own that says
    /// "Ține de… O mașină", on a car's page), in the binder's order.
    var categoryPockets: [PagePocket] {
        guard let role = definition.behavior.role else { return [] }
        return templates
            .filter { $0.behavior.hasPocketOfItsOwn && $0.behavior.mayBelongTo == role }
            .sorted { ($0.homeOrder, $0.key) < ($1.homeOrder, $1.key) }
            .map { PagePocket.category(key: $0.key, name: $0.name) }
    }

    /// The page's pockets in its one order: what the category lists, with the categories' own.
    func pockets(listing listed: [SectionPocket]) -> [PagePocket] {
        PagePocket.ordered(listed: listed, categories: categoryPockets)
    }

    func fill(_ pocket: PagePocket) -> PocketFill {
        switch pocket {
        case .listed(.upcoming):
            return UpcomingPocket.listed(asset).isEmpty ? .empty : .filled
        case .category, .listed(.tenants), .listed(.products), .listed(.subscriptions), .listed(.plants):
            let children = ChildrenPocket.contents(of: asset, pocket: pocket, templates: templates)
            if !children.children.isEmpty { return .filled }
            return children.isOffered ? .empty : .notOffered
        case .listed(.documents):
            return SectionPapers.isEmpty(asset, templates: templates) ? .empty : .filled
        case .listed(.history):
            return (asset.history ?? []).isEmpty ? .empty : .filled
        case .listed(.people):
            return providers.isEmpty ? .empty : .filled
        case .listed(.money):
            return MoneyPocket.Facts.make(asset: asset, definition: definition).isEmpty ? .empty : .filled
        case .listed(.keyFacts):
            return DocumentPageFacts.keyFactRows(of: asset, definition: definition).isEmpty ? .empty : .filled
        }
    }

    /// What the pocket's own button adds, which is also what the page's menu offers for it.
    func addition(_ pocket: PagePocket) -> PocketAddition? {
        switch pocket {
        case .listed(.upcoming):
            return .deadline
        case .category, .listed(.tenants), .listed(.products), .listed(.subscriptions), .listed(.plants):
            guard let key = ChildrenPocket.contents(of: asset, pocket: pocket, templates: templates).childKey else { return nil }
            return .child(pocket, templateKey: key)
        case .listed(.documents):
            return PocketAddition.documentButtons(isHolder: isHolder).first
        case .listed(.history):
            return PocketAddition.history(of: definition.behavior)
        case .listed(.people):
            return .person
        case .listed(.money):
            return nil
        case .listed(.keyFacts):
            return .keyFact
        }
    }

    /// What the pocket's own buttons add, under its rows: Acte's (`PocketAddition.documentButtons`), else the
    /// one the menu offers for it.
    func buttons(_ pocket: PagePocket) -> [PocketAddition] {
        if pocket == .listed(.documents) { return PocketAddition.documentButtons(isHolder: isHolder) }
        return addition(pocket).map { [$0] } ?? []
    }

    /// The page's layout, from the pockets its category lists (`listed`) and the categories' own.
    func layout(pockets listed: [SectionPocket], revealed: Set<PagePocket> = [], folds: Bool = SectionPageLayout.foldsEmptyPockets) -> SectionPageLayout {
        SectionPageLayout.make(pockets: pockets(listing: listed), revealed: revealed, folds: folds, fill: { fill($0) }, addition: { addition($0) })
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
