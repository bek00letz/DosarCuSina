import Foundation

// Every word a section page's pockets and its „Adaugă…” menu say (`SectionPockets.swift` and
// `SectionPocketLayout.swift` hold none of their own: they are a shaped screen). What depends on
// the category's visits is its kind's (`VisitKind.pocketWords`); what depends on the pocket alone
// is the pocket's (`SectionPocket.emptyLine`, `PocketAddition.title`); the rest every page shares
// (`PocketWording`). `docs/COPY_MATRIX.md` lists them for every category (`CopyMatrixTests.pocketsSection`).

// MARK: - A pocket while it is empty

extension SectionPocket {
    /// The line inside the pocket while it holds nothing, on a page of the category `definition`:
    /// Istoric's and Oameni's in the words of its visits (`VisitKind.pocketWords`), Acte's naming
    /// the papers its sections keep (`CaptureKindProfile.papersKept(inCategory:)`), the others'
    /// the pocket's own. Every pocket written.
    func emptyLine(in definition: TemplateDefinition) -> String {
        let visits = definition.behavior.visit
        return switch self {
        case .upcoming:
            String(localized: "Niciun termen. Adaugă unul și îți amintesc la timp.", comment: "Empty Urmează pocket.")
        case .tenants:
            String(localized: "Niciun chiriaș. Adaugă contractul și îți spun când se termină.", comment: "Empty Chiriași pocket.")
        case .products:
            String(localized: "Niciun produs. Adaugă aragazul sau centrala și ții minte garanția.", comment: "Empty Produse pocket.")
        case .subscriptions:
            String(localized: "Niciun abonament trecut aici.", comment: "Empty Abonamente pocket.")
        case .plants:
            String(localized: "Nicio plantă trecută aici. Adaug-o și îți amintesc de udat.", comment: "Empty Plante pocket on a home's page.")
        case .documents:
            PocketWording.documentsEmpty(CaptureKindProfile.papersKept(inCategory: definition.key))
        case .history:
            visits.pocketWords.historyEmpty
        case .people:
            visits.pocketWords.peopleEmpty
        case .money:
            String(localized: "Nicio sumă notată încă. Când notezi ceva cu preț, apare aici.", comment: "Empty Bani pocket.")
        case .keyFacts:
            String(localized: "Pune aici ce cauți des, un număr sau un cod. Un cod sau o parolă rămân ascunse, ca un PIN.",
                   comment: "Empty Date importante pocket, the same for every category.")
        }
    }

    /// The button that files a new section in the pocket, for the pockets of the catalog's that
    /// hold sections; nil for the others, which a section is never filed in (they read as
    /// „Adaugă în „…””, `PocketWording.addInto`).
    var addsSectionTitle: String? {
        switch self {
        case .tenants: String(localized: "Adaugă un chiriaș", comment: "Button in the Chiriași pocket.")
        case .products: String(localized: "Adaugă un produs", comment: "Button in the Produse pocket.")
        case .subscriptions: String(localized: "Adaugă un abonament", comment: "Button in the Abonamente pocket.")
        case .plants: String(localized: "Adaugă o plantă", comment: "Button in the Plante pocket of a home's page.")
        case .upcoming, .documents, .history, .people, .money, .keyFacts: nil
        }
    }
}

extension PagePocket {
    /// The line inside the pocket while it holds nothing (`SectionPocket.emptyLine`); a category's
    /// own pocket names the category.
    func emptyLine(in definition: TemplateDefinition) -> String {
        switch self {
        case .listed(let pocket): pocket.emptyLine(in: definition)
        case .category(_, let name): PocketWording.categoryEmpty(name)
        }
    }
}

// MARK: - What can be added

extension PocketAddition {
    /// Its button's and its menu item's title.
    var title: String {
        switch self {
        case .deadline:
            String(localized: "Adaugă un termen", comment: "Adds a deadline to a section, from its Urmează pocket or its add menu.")
        case .child(.listed(let pocket), _):
            pocket.addsSectionTitle ?? PocketWording.addInto(pocket.title)
        case .child(.category(_, let name), _):
            PocketWording.addInto(name)
        case .personalDocument:
            String(localized: "Adaugă un act", comment: "Adds a document for a household member.")
        case .paper(let besidePersonal):
            besidePersonal
                ? String(localized: "Scanează un document", comment: "Adds a photo of another paper on a person's page, beside their own documents.")
                : String(localized: "Adaugă un act", comment: "Adds a photo of a paper to a section, from its Acte pocket or its add menu.")
        case .visit(let kind):
            // Offered only where the kind has visits (`history(of:)`); the copy matrix checks no
            // addition is left without words.
            kind.shape?.title ?? ""
        case .note:
            String(localized: "Adaugă o notă")
        case .person:
            String(localized: "Adaugă o persoană", comment: "Adds someone who looks after a section.")
        case .keyFact:
            String(localized: "Adaugă un rând", comment: "Adds a row of one's own under Date importante.")
        }
    }

    /// The symbol beside its title.
    var systemImage: String {
        switch self {
        case .deadline: "calendar.badge.plus"
        case .child: "plus"
        case .personalDocument: "person.text.rectangle"
        case .paper: "doc.viewfinder"
        case .visit(let kind): kind.shape?.symbol ?? "wrench.and.screwdriver"
        case .note: "note.text.badge.plus"
        case .person: "person.badge.plus"
        case .keyFact: "list.bullet.rectangle"
        }
    }
}

// MARK: - What every page shares

enum PocketWording {
    /// The page's one row for its empty pockets.
    static var addMenu: String {
        String(localized: "Adaugă…", comment: "Row on a section page whose menu adds to its empty parts: a deadline, a document, a visit…")
    }

    /// A button that files a section in a pocket named after its category (a car's Anvelope).
    static func addInto(_ name: String) -> String {
        String(localized: "Adaugă în „\(name)”", comment: "Button in the pocket of a category of one's own on its parent's page (a car's Anvelope): adds a section of it here.")
    }

    /// Inside Acte while it holds nothing, naming the papers the category's sections keep, up to
    /// three („Scanează talonul, polița sau raportul ITP și le găsești aici.”), agreeing with the one
    /// paper when there is one („Scanează contractul și îl găsești aici.”), else any paper.
    static func documentsEmpty(_ papers: [CaptureKindProfile.Noun]) -> String {
        guard let first = papers.first else {
            return String(localized: "Niciun document. Scanează un act și îl găsești aici.",
                          comment: "Empty Acte pocket of a category whose sections keep no paper of their own kind.")
        }
        guard papers.count > 1 else {
            return switch first.gender {
            case .masculine:
                String(localized: "Niciun document. Scanează \(first.itself) și îl găsești aici.",
                       comment: "Empty Acte pocket: the one paper its sections keep, named by a masculine noun with its article (contractul).")
            case .feminine:
                String(localized: "Niciun document. Scanează \(first.itself) și o găsești aici.",
                       comment: "Empty Acte pocket: the one paper its sections keep, named by a feminine noun with its article (polița).")
            case .plural:
                String(localized: "Niciun document. Scanează \(first.itself) și le găsești aici.",
                       comment: "Empty Acte pocket: the papers its sections keep, named by a plural noun with its article.")
            }
        }
        let list = papers.prefix(3).map(\.itself).formatted(.list(type: .or).locale(.dosarDefault))
        return String(localized: "Niciun document. Scanează \(list) și le găsești aici.",
                      comment: "Empty Acte pocket: the papers its sections keep, as a list ending in „sau” (talonul, polița sau raportul ITP).")
    }

    /// Inside a category's own pocket while it holds nothing.
    static func categoryEmpty(_ name: String) -> String {
        String(localized: "Nimic din „\(name)” trecut aici.", comment: "Empty pocket of a category of one's own on its parent's page (a car's Anvelope).")
    }

    // MARK: A section filed under the page

    /// Its line: valid or contracted until a day.
    static func until(_ day: String) -> String {
        String(localized: "până la \(day)", comment: "Child summary: valid or contracted until a date.")
    }

    /// Its line: under warranty until a day.
    static func warrantyUntil(_ day: String) -> String {
        String(localized: "garanție până la \(day)", comment: "Child summary: warranty until a date.")
    }

    // MARK: A paper in Acte

    /// Its line: the day it stops being valid, still to come. A verb, so it agrees with any
    /// paper („Polița”, „Talonul”, „Rezultatele”).
    static func expires(_ day: String) -> String {
        String(localized: "Expiră pe \(day)", comment: "Document row: the day a paper stops being valid, still to come.")
    }

    /// Its line: the day it stopped being valid, passed.
    static func expired(_ day: String) -> String {
        String(localized: "A expirat pe \(day)", comment: "Document row: the day a paper stopped being valid, passed.")
    }

    /// Its line: the day printed on it.
    static func dated(_ day: String) -> String {
        String(localized: "Din \(day)", comment: "Document row: the date on the document.")
    }

    // MARK: Bani

    static var monthly: String { String(localized: "Pe lună", comment: "Money row: monthly equivalent of a subscription.") }
    static var lastBill: String { String(localized: "Ultima factură", comment: "Money row: a subscription's newest bill.") }
    static var averageBill: String { String(localized: "În medie, pe factură", comment: "Money row: a subscription's average bill over the last year.") }
    static var lastYear: String { String(localized: "În ultimul an", comment: "Money row: spent in the last 12 months.") }
    static var allTime: String { String(localized: "În total", comment: "Money row: spent in total, since the section is in the binder. Agrees with no noun, so it fits every section.") }
    static var purchasePrice: String { String(localized: "Preț de cumpărare", comment: "Money row: purchase price.") }
}

// MARK: - What a paper is

extension DocumentKind {
    /// Its name, where a paper has no title of its own.
    var title: String {
        switch self {
        case .invoice: String(localized: "Factură")
        case .receipt: String(localized: "Bon")
        case .policy: String(localized: "Poliță")
        case .contract: String(localized: "Contract")
        case .certificate: String(localized: "Certificat")
        case .report: String(localized: "Raport")
        case .identity: String(localized: "Act de identitate")
        case .warranty: String(localized: "Certificat de garanție")
        case .manual: String(localized: "Manual")
        case .prescription: String(localized: "Rețetă")
        case .photo: String(localized: "Poză")
        case .other: String(localized: "Document")
        }
    }

    /// Its symbol, in a paper's row.
    var systemImage: String {
        switch self {
        case .invoice, .receipt: "doc.text"
        case .policy, .contract: "doc.richtext"
        case .certificate, .warranty: "checkmark.seal"
        case .report: "doc.plaintext"
        case .identity: "person.text.rectangle"
        case .manual: "book"
        case .prescription: "cross.case"
        case .photo: "photo"
        case .other: "doc"
        }
    }
}
