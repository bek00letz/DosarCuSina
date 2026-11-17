import Foundation

/// The words the full lists behind a pocket's „Vezi tot” say the same way for every category
/// (`SectionLists.swift` holds none of its own: it is a shaped screen). A list's empty line is
/// its pocket's (`SectionPocket.emptyLine(in:)`), in the category's words. `docs/COPY_MATRIX.md`
/// lists them with the pockets (`CopyMatrixTests.pocketsSection`).
enum SectionListWording {
    // MARK: Termene

    static var deadlines: String { String(localized: "Termene", comment: "Header of the obligations list.") }
    static var suggestions: String { String(localized: "Poți adăuga", comment: "Header of suggested obligations.") }
    static func suggestionsFor(_ section: String) -> String {
        String(localized: "Sugestii pentru „\(section)”. Le poți schimba oricând.", comment: "Footer of suggested obligations.")
    }
    static var anotherDeadline: String { String(localized: "Alt termen", comment: "Adds an obligation that isn't in the suggestions.") }
    static var add: String { String(localized: "Adaugă", comment: "Adds a suggested obligation.") }

    /// The first date a usual deadline asks, when it can't work it out alone.
    static func nextDateQuestion(_ deadline: String) -> String {
        String(localized: "Când e următoarea dată pentru „\(deadline)”?", comment: "Question when adding an obligation that needs a date.")
    }
    static var date: String { String(localized: "Data") }
    static var dateFootnote: String {
        String(localized: "De exemplu, data până la care e valabil actul de acum.", comment: "Under the first date of a usual deadline, for any category.")
    }

    // MARK: Istoric

    static var lastTime: String { String(localized: "Ultima dată", comment: "Header: the last time each part was done.") }
    static var wholeHistory: String { String(localized: "Tot istoricul", comment: "Header: every history entry.") }

    // MARK: Acte

    static var personalDocuments: String { String(localized: "Acte personale", comment: "Header: personal documents.") }
    static var documents: String { String(localized: "Documente", comment: "Header: scanned documents.") }
    static var archived: String { String(localized: "Arhivate", comment: "Header: documents kept for reference.") }
    /// Under the archived papers, naming the papers the category's sections keep, up to three
    /// („Acte vechi, ca talonul, polița sau raportul ITP, păstrate…”), as Acte's empty line does
    /// (`CaptureKindProfile.papersKept(inCategory:)`); any paper when it keeps none of its own.
    static func archivedFootnote(_ papers: [CaptureKindProfile.Noun]) -> String {
        guard !papers.isEmpty else {
            return String(localized: "Acte vechi, păstrate pentru orice eventualitate.",
                          comment: "Footer of archived documents, in a category whose sections keep no paper of their own kind.")
        }
        let list = papers.prefix(3).map(\.itself).formatted(.list(type: .or).locale(.dosarDefault))
        return String(localized: "Acte vechi, ca \(list), păstrate pentru orice eventualitate.",
                      comment: "Footer of archived documents: the papers the category's sections keep, as a list ending in „sau” (talonul, polița sau raportul ITP).")
    }
}
