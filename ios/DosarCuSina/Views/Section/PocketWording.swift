import Foundation

// Every word a section page's pockets and its „Adaugă…” menu say (`SectionPockets.swift` and
// `SectionPocketLayout.swift` hold none of their own: they are a shaped screen). What depends on
// the category's visits is its kind's (`VisitKind.pocketWords`); what depends on the pocket alone
// is the pocket's (`SectionPocket.emptyLine`, `PocketAddition.title`); the rest every page shares
// (`PocketWording`). `docs/COPY_MATRIX.md` lists them for every category (`CopyMatrixTests.pocketsSection`).

// MARK: - A pocket while it is empty

extension SectionPocket {
    /// The line inside the pocket while it holds nothing, on a page of a category whose visits
    /// are `visits`: Istoric's and Oameni's in the kind's words, the others' the pocket's own.
    /// Every pocket written.
    func emptyLine(visits: VisitKind) -> String {
        switch self {
        case .upcoming:
            String(localized: "Niciun termen. Adaugă unul ca să îți amintim la timp.", comment: "Empty Urmează pocket.")
        case .tenants:
            String(localized: "Niciun chiriaș. Adaugă contractul și îți spunem când se termină.", comment: "Empty Chiriași pocket.")
        case .products:
            String(localized: "Niciun produs. Adaugă aragazul sau centrala și ții minte garanția.", comment: "Empty Produse pocket.")
        case .subscriptions:
            String(localized: "Niciun abonament trecut aici.", comment: "Empty Abonamente pocket.")
        case .plants:
            String(localized: "Nicio plantă trecută aici. Adaug-o și îți amintim de udat.", comment: "Empty Plante pocket on a home's page.")
        case .documents:
            String(localized: "Niciun document. Scanează polița, factura sau certificatul și le găsești aici.", comment: "Empty Acte pocket.")
        case .history:
            visits.pocketWords.historyEmpty
        case .people:
            visits.pocketWords.peopleEmpty
        case .money:
            String(localized: "Nicio sumă notată încă. Când notezi ceva cu preț, apare aici.", comment: "Empty Bani pocket.")
        case .keyFacts:
            String(localized: "Pune aici ce cauți des: numărul poliței, codul de client. Un cod sau o parolă rămân ascunse, ca un PIN.",
                   comment: "Empty Date importante pocket.")
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
    func emptyLine(visits: VisitKind) -> String {
        switch self {
        case .listed(let pocket): pocket.emptyLine(visits: visits)
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

    /// Its line: valid until a day.
    static func validUntil(_ day: String) -> String {
        String(localized: "Valabil până la \(day)", comment: "Document row: valid until.")
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
    static var allTime: String { String(localized: "De când îl ai", comment: "Money row: spent in total.") }
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
