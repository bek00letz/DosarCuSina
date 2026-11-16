import Foundation

/// Every word the form for a category of one's own says (`CustomCategoryForm`, a shaped screen
/// that holds none of its own): the same for every category, and, for what its service counts
/// by, the counter's (`CategorySwitches.Counter`, below). `docs/COPY_MATRIX.md` lists them
/// (`CopyMatrixTests.customCategorySection`).
enum CustomCategoryWording {
    // MARK: Its name and symbol

    static var name: String { String(localized: "Cum se numește") }
    static var namePrompt: String { String(localized: "Barca, Rulota, Pianul") }
    static var symbol: String { String(localized: "Simbol") }

    /// A symbol's name for VoiceOver, from the symbol's own: „car side” for `car.side.fill`.
    static func spokenName(ofSymbol symbol: String) -> String {
        symbol.replacingOccurrences(of: ".fill", with: "").replacingOccurrences(of: ".", with: " ")
    }

    // MARK: What it keeps

    static var keeps: String { String(localized: "Ce ține minte") }
    static var documents: String { String(localized: "Are acte", comment: "Switch of a category of one's own: its sections keep documents.") }
    static var documentsHint: String { String(localized: "Poze și PDF-uri: acte, contracte, garanții.", comment: "Explains the documents switch.") }
    static var bills: String {
        String(localized: "Are facturi și contracte", comment: "Switch of a category of one's own: its sections keep subscriptions and their bills.")
    }
    static var billsHint: String {
        String(localized: "Abonamente cu facturile lor, ca la o locuință: curent, internet, loc de parcare.", comment: "Explains the bills switch.")
    }
    static var service: String {
        String(localized: "Are revizii sau lucrări", comment: "Switch of a category of one's own: its sections have a regular service or job, logged as visits.")
    }
    static var serviceHint: String {
        String(localized: "Le notezi în istoric și îți amintesc din timp, ca la mașină.", comment: "Explains the service switch: visits and a reminder.")
    }
    static var serviceCounter: String { String(localized: "Revizia se face", comment: "VoiceOver label of the service counter choice.") }
    static var wholeNumber: LocalizedStringResource { LocalizedStringResource("Scrie un număr întreg, mai mare ca zero.") }

    // MARK: Ține de…

    static var belongs: String { String(localized: "Ține de…") }
    static var belongsLabel: String {
        String(localized: "Ține de", comment: "VoiceOver label of the choice of what a category's sections belong to.")
    }
    static var belongsToNothing: String {
        String(localized: "Nimic", comment: "„Ține de…” choice of a category of one's own: its sections stand on their own.")
    }
    static var belongsFootnote: String {
        String(localized: "Fiecare apare și pe pagina celei de care ține și se adaugă și de acolo.",
               comment: "Explains „Ține de…”: each section shows on the page of the home, car or person it belongs to, and can be added from there.")
    }

    // MARK: Boxes

    static var boxes: String { String(localized: "Pe ecranul Dosar") }
    static var boxEach: String { String(localized: "Câte o cutie pentru fiecare", comment: "Boxes choice: one box per section.") }
    static var boxEachHint: String { String(localized: "Ca la mașini: fiecare are cutia ei.", comment: "Explains one box per section.") }
    static var boxAll: String {
        String(localized: "O cutie pentru toate", comment: "Boxes choice: one box for all of a category's sections, wherever they are filed.")
    }
    static var boxAllHint: String { String(localized: "Ca la plante: toate stau la un loc.", comment: "Explains one box for all of a category's sections.") }

    // MARK: Its line in a list of categories

    /// One line saying what a category keeps, for a list of categories: „Acte · Revizii după ore”.
    static func summary(of switches: CategorySwitches) -> String {
        var parts: [String] = []
        if switches.hasDocuments { parts.append(String(localized: "Acte", comment: "Summary of a category of one's own: it keeps documents.")) }
        if switches.hasBills { parts.append(String(localized: "Facturi și contracte", comment: "Summary of a category of one's own: it keeps subscriptions.")) }
        if let counter = switches.service?.counter { parts.append(counter.summary) }
        if let role = switches.belongsTo {
            parts.append(String(localized: "Ține de: \(BelongingWording.option(role).lowercased(with: .dosarDefault))",
                                comment: "Summary of a category of one's own: what its sections belong to (o mașină)."))
        }
        if parts.isEmpty { return String(localized: "Termene și date importante", comment: "Summary of a category of one's own that keeps nothing more.") }
        return parts.joined(separator: " · ")
    }
}

extension CategorySwitches.Counter {
    /// Its choice under „Are revizii sau lucrări”.
    var title: String {
        switch self {
        case .time: String(localized: "După timp", comment: "Service choice: every so many months.")
        case .kilometres: String(localized: "După kilometri", comment: "Service choice: by kilometres.")
        case .engineHours: String(localized: "După orele de motor", comment: "Service choice: by engine hours.")
        }
    }

    /// Under its choice: what it fits.
    var subtitle: String {
        switch self {
        case .time: String(localized: "Fără contor, de obicei o dată pe an: un pian, o centrală.", comment: "Service choice explained: by time.")
        case .kilometres: String(localized: "Ții kilometrajul la zi: o rulotă, o motocicletă.", comment: "Service choice explained: by kilometres.")
        case .engineHours: String(localized: "Ții orele la zi: o barcă, un generator.", comment: "Service choice explained: by engine hours.")
        }
    }

    /// How often, asked once it is chosen.
    var everyTitle: String {
        switch self {
        case .time: String(localized: "La câte luni?")
        case .kilometres: String(localized: "La câți km?")
        case .engineHours: String(localized: "La câte ore?")
        }
    }

    /// Under how often.
    var everyFootnote: String {
        switch self {
        case .time: String(localized: "Îți amintesc din timp de fiecare revizie.")
        case .kilometres, .engineHours: String(localized: "Sau o dată pe an, ce vine întâi.")
        }
    }

    /// Its part of a category's line in a list of categories.
    var summary: String {
        switch self {
        case .time: String(localized: "Revizii după timp", comment: "Summary of a category of one's own: a service every so many months.")
        case .kilometres: String(localized: "Revizii după kilometri", comment: "Summary of a category of one's own: a service by kilometres.")
        case .engineHours: String(localized: "Revizii după ore", comment: "Summary of a category of one's own: a service by engine hours.")
        }
    }
}
