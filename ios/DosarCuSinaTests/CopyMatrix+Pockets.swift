import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// The section page's pockets in `docs/COPY_MATRIX.md`: for every category the matrix shows, the
/// pockets its page lists in their one order, what its „Adaugă…” menu offers while the page holds
/// nothing, and what each pocket says while it is empty, with its own buttons. All of it read from
/// the descriptions the page draws (`SectionPocket.emptyLine`, Istoric's and Oameni's from the
/// category's visit kind, `VisitKind.pocketWords`; `PocketAddition.title`; `PocketWording`),
/// through the page's own rule (`PocketContents`), never written here.
extension CopyMatrixTests {
    /// One pocket of a page with nothing in it yet.
    struct PocketEntry {
        var pocket: PagePocket
        /// Empty, or not offered at all (plants while the household keeps none).
        var fill: PocketFill
        /// Its line while it holds nothing.
        var empty: String
        /// What its own buttons add, under its rows.
        var buttons: [PocketAddition]
    }

    /// One category's page with nothing in it yet.
    struct PocketPage {
        var category: Category
        /// Its pockets in the page's one order.
        var entries: [PocketEntry]
        /// What „Adaugă…” offers: the empty pockets' additions, in their order.
        var menu: [PocketAddition]

        /// Everything the page can add, from the menu and the pockets' own buttons.
        var additions: [PocketAddition] { menu + entries.flatMap(\.buttons) }

        /// One addition as the menu shows it: its title, the pocket named under it.
        static func menuItem(_ addition: PocketAddition) -> String {
            addition.menuDetail.map { "\(addition.title) (\($0))" } ?? addition.title
        }

        /// The page, row by row.
        var rows: [(String, String)] {
            var rows: [(String, String)] = [
                ("Its visits", "`\(category.definition.behavior.visit.rawValue)`"),
                ("Its pockets, in order", entries.map(\.pocket.title).joined(separator: " · ")),
                ("„Adaugă…” on an empty page", menu.map(Self.menuItem).joined(separator: " · ")),
            ]
            for entry in entries {
                var place = "\(entry.pocket.title), empty"
                if entry.fill == .notOffered {
                    place += " (not offered until the household keeps them)"
                } else if !menu.contains(where: { $0.pocket == entry.pocket }) {
                    place += " (not drawn until it holds something)"
                }
                let buttons = entry.buttons.map(\.title).joined(separator: " / ")
                rows.append((place, buttons.isEmpty ? entry.empty : "\(entry.empty) — \(buttons)"))
            }
            if entries.contains(where: { $0.pocket == .listed(.documents) }) {
                let papers = CaptureKindProfile.papersKept(inCategory: category.definition.key)
                rows.append(("Acte's full list, under the archived", "\(SectionListWording.archived) — \(SectionListWording.archivedFootnote(papers))"))
            }
            return rows
        }

        /// Every word the page says for its category, without the shared frame.
        var words: String { rows.map(\.1).joined(separator: " ") }
    }

    /// Every category's page, with nothing in it yet, laid out by the page's own rule.
    @MainActor
    static func pocketPages(_ categories: [Category]) throws -> [PocketPage] {
        let context = try makeContext()
        let templates = try TemplateStore(context: context).all()
        return categories.map { category in
            let definition = category.definition
            let asset = Asset(name: "Secțiune", templateKey: definition.key)
            context.insert(asset)
            let contents = PocketContents(asset: asset, definition: definition, templates: templates, providers: [])
            let entries = contents.pockets(listing: definition.pockets).map { pocket in
                PocketEntry(pocket: pocket, fill: contents.fill(pocket),
                            empty: pocket.emptyLine(in: definition), buttons: contents.buttons(pocket))
            }
            let menu = contents.layout(pockets: definition.pockets, folds: true).additions
            return PocketPage(category: category, entries: entries, menu: menu)
        }
    }

    /// What every page says alike.
    static var pocketsSharedRows: [(String, String)] {
        let day = DosarFormat.day(CalendarDay("2027-05-03"))
        let money = [PocketWording.monthly, PocketWording.lastBill, PocketWording.averageBill,
                     PocketWording.lastYear, PocketWording.allTime, PocketWording.purchasePrice]
        return [
            ("The menu's row", PocketWording.addMenu),
            ("A pocket named after a category of one's own (a car's „Anvelope”)",
             "\(PocketWording.categoryEmpty("Anvelope")) — \(PocketWording.addInto("Anvelope"))"),
            ("A section filed under the page", "\(PocketWording.until(day)) / \(PocketWording.warrantyUntil(day))"),
            ("A paper in Acte", "\(PocketWording.expires(day)) / \(PocketWording.expired(day)) / \(PocketWording.dated(day))"),
            ("A paper with no title of its own", DocumentKind.allCases.map(\.title).joined(separator: ", ")),
            ("Bani's rows", money.joined(separator: " · ")),
            ("The full lists („Vezi tot”; empty, each says its pocket's line)",
             "\(SectionListWording.deadlines) · \(SectionListWording.lastTime) · \(SectionListWording.wholeHistory) · "
                + "\(SectionListWording.personalDocuments) · \(SectionListWording.documents) · \(SectionListWording.archived) "
                + "(its line under it is the category's) · \(SectionListWording.add)"),
            ("The full list's suggestions (off, `ObligationListScreen.offersSuggestionRows`)",
             "\(SectionListWording.suggestions) — \(SectionListWording.suggestionsFor("Golful")) · \(SectionListWording.anotherDeadline) · "
                + "\(SectionListWording.nextDateQuestion("ITP")) \(SectionListWording.date) — \(SectionListWording.dateFootnote)"),
        ]
    }

    /// The matrix's section for the section page's pockets.
    @MainActor
    static func pocketsSection(_ categories: [Category]) throws -> String {
        var out = """
        ## The section page's pockets

        What a section's page says in its pockets and its „Adaugă…” menu while it holds nothing yet: \
        each pocket's line from `SectionPocket.emptyLine` (Istoric's and Oameni's from the category's \
        visit kind, `VisitKind.pocketWords`), what it adds from `PocketAddition.title`. An empty pocket \
        folds into „Adaugă…” (`SectionPageLayout.foldsEmptyPockets`); its line shows with the way back, \
        or while the person adds to it right there.

        ### What every page shares

        \(table(pocketsSharedRows))

        """
        for page in try pocketPages(categories) {
            out += "\n### \(page.category.title)\n\n" + table(page.rows) + "\n"
        }
        return out
    }
}

/// The rules the pockets' matrix makes checkable: every category's page says only what fits it.
@MainActor
@Suite("Copy matrix: pockets")
struct PocketsCopyRulesTests {
    private func pages() throws -> [CopyMatrixTests.PocketPage] {
        try CopyMatrixTests.pocketPages(CopyMatrixTests.categories())
    }

    @Test("Vehicle words only on a page whose visits are a service")
    func vehicleWordsStayWithVehicles() throws {
        for page in try pages() where page.category.definition.behavior.visit != .service {
            let tokens = CopyMatrixTests.tokens(page.words)
            #expect(tokens.isDisjoint(with: CopyMatrixTests.vehicleWords), "\(page.category.title): \(tokens.intersection(CopyMatrixTests.vehicleWords).sorted())")
        }
    }

    @Test("A doctor's and a vet's words only on a page whose visits are theirs")
    func careWordsStayWithHealthAndPets() throws {
        for page in try pages() {
            let kind = page.category.definition.behavior.visit
            guard kind != .doctor, kind != .vet else { continue }
            let tokens = CopyMatrixTests.tokens(page.words)
            #expect(tokens.isDisjoint(with: CopyMatrixTests.careWords), "\(page.category.title): \(tokens.intersection(CopyMatrixTests.careWords).sorted())")
        }
    }

    @Test("Nothing a page adds or says is left without words")
    func noEmptyWords() throws {
        for page in try pages() {
            for addition in page.additions {
                #expect(!addition.title.isEmpty, "\(page.category.title): \(addition) has no title")
                #expect(addition.menuDetail?.isEmpty != true, "\(page.category.title): \(addition) names an empty pocket")
            }
            for entry in page.entries {
                #expect(!entry.empty.isEmpty, "\(page.category.title): \(entry.pocket.title) says nothing while empty")
            }
            #expect(!page.menu.isEmpty, "\(page.category.title): an empty page offers something to add")
        }
    }

    @Test("No visit is offered where the kind has none, and Istoric offers the kind's own")
    func visitsOnlyWhereTheKindHasThem() throws {
        for page in try pages() {
            let kind = page.category.definition.behavior.visit
            let visits = page.additions.filter { if case .visit = $0 { true } else { false } }
            if kind.offersVisit {
                #expect(visits.allSatisfy { $0 == .visit(kind) }, "\(page.category.title): \(visits)")
            } else {
                #expect(visits.isEmpty, "\(page.category.title): \(visits)")
            }
            if let history = page.entries.first(where: { $0.pocket == .listed(.history) }) {
                #expect(history.buttons == (PocketAddition.history(of: page.category.definition.behavior).map { [$0] } ?? []), "\(page.category.title)")
            }
        }
    }

    @Test("Istoric and Oameni say what the category's visit kind says")
    func historyAndPeopleFollowTheKind() throws {
        for page in try pages() {
            let words = page.category.definition.behavior.visit.pocketWords
            for entry in page.entries {
                switch entry.pocket {
                case .listed(.history): #expect(entry.empty == words.historyEmpty, "\(page.category.title)")
                case .listed(.people): #expect(entry.empty == words.peopleEmpty, "\(page.category.title)")
                default: break
                }
            }
        }
    }

    @Test("Acte names the papers its category's sections keep, as capture files them, agreeing with one")
    func documentsNameTheirPapers() throws {
        for page in try pages() {
            guard let documents = page.entries.first(where: { $0.pocket == .listed(.documents) }) else { continue }
            let papers = CaptureKindProfile.papersKept(inCategory: page.category.definition.key)
            #expect(documents.empty == PocketWording.documentsEmpty(papers), "\(page.category.title)")
            for paper in papers.prefix(3) {
                #expect(documents.empty.contains(paper.itself), "\(page.category.title): „\(documents.empty)” leaves out „\(paper.itself)”")
            }
        }
        let car = CaptureKindProfile.papersKept(inCategory: BuiltInTemplates.Key.vehicle).map(\.itself)
        #expect(car.contains("talonul") && car.contains("polița") && !car.contains("factura"), "A car keeps its talon and policy; a service's invoice is the visit's: \(car)")
        let lines = Set(try pages().compactMap { $0.entries.first { $0.pocket == .listed(.documents) }?.empty })
        #expect(lines.count > 1, "Not one line for every category")
    }

    @Test("Every visit kind says its own Istoric and Oameni")
    func everyKindHasItsOwnWords() {
        let words = VisitKind.allCases.map(\.pocketWords)
        #expect(Set(words.map(\.historyEmpty)).count == VisitKind.allCases.count, "One Istoric line per kind")
        #expect(Set(words.map(\.peopleEmpty)).count == VisitKind.allCases.count, "One Oameni line per kind")
        #expect(words.allSatisfy { !$0.historyEmpty.isEmpty && !$0.peopleEmpty.isEmpty })
    }

    @Test("The section is written for every category the matrix shows")
    func sectionListsEveryCategory() throws {
        let categories = try CopyMatrixTests.categories()
        let section = try CopyMatrixTests.pocketsSection(categories)
        #expect(section.hasPrefix("## The section page's pockets"))
        for category in categories {
            #expect(section.contains("\n### \(category.title)\n"), "\(category.title)")
        }
    }
}
