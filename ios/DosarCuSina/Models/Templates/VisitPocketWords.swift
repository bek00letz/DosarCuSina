import Foundation

/// What a section page's pockets say that depends on its category's visits (`VisitKind.pocketWords`):
/// Istoric holds the visits (or a plant's notes, or only what closes at a deadline), Oameni the
/// ones who come or are gone to (the service, a tradesperson, the doctor, the vet). The one place
/// that says it, as `VisitShape` says what the visit form asks; the pockets (`SectionPocket.emptyLine`)
/// draw it, and `docs/COPY_MATRIX.md` lists it for every category (`CopyMatrixTests.pocketsSection`).
struct VisitPocketWords: Hashable, Sendable {
    /// Inside Istoric while nothing is in it.
    var historyEmpty: String
    /// Inside Oameni while no one is in it.
    var peopleEmpty: String
}

extension VisitKind {
    /// What the page's pockets say for this kind, every kind written. The way back
    /// (`VisitShape.formsByKind` off) gives every kind the words of before.
    var pocketWords: VisitPocketWords {
        guard VisitShape.formsByKind else { return .everyKindBefore }
        switch self {
        case .service:
            return VisitPocketWords(
                historyEmpty: String(localized: "Nimic notat încă. După fiecare service, notează aici ce s-a făcut, cât a costat și cine a lucrat.",
                                     comment: "Empty Istoric pocket of a car or a bike."),
                peopleEmpty: String(localized: "Nimeni încă. Adaugă service-ul sau mecanicul și ai numărul la îndemână.",
                                    comment: "Empty Oameni pocket of a car or a bike.")
            )
        case .job:
            return VisitPocketWords(
                historyEmpty: String(localized: "Nimic notat încă. Când vine un meseriaș, notează aici ce a lucrat, cât a costat și cine a fost.",
                                     comment: "Empty Istoric pocket of a home or of a category whose jobs go by time."),
                peopleEmpty: String(localized: "Nimeni încă. Adaugă meseriașii la care apelezi și ai numărul la îndemână.",
                                    comment: "Empty Oameni pocket of a home or of a category whose jobs go by time.")
            )
        case .repair:
            return VisitPocketWords(
                historyEmpty: String(localized: "Nicio reparație notată încă. După una, notează aici ce s-a reparat, unde și cât a costat.",
                                     comment: "Empty Istoric pocket of something bought (Garanții)."),
                peopleEmpty: String(localized: "Nimeni încă. Adaugă atelierul sau magazinul și ai numărul la îndemână.",
                                    comment: "Empty Oameni pocket of something bought (Garanții).")
            )
        case .upkeep:
            return VisitPocketWords(
                historyEmpty: String(localized: "Nicio revizie notată încă. După una, notează aici ce s-a făcut și cât a costat, dacă a costat.",
                                     comment: "Empty Istoric pocket of an espresso machine."),
                peopleEmpty: String(localized: "Nimeni încă. Adaugă cine îl repară când e nevoie și ai numărul la îndemână.",
                                    comment: "Empty Oameni pocket of an espresso machine.")
            )
        case .doctor:
            return VisitPocketWords(
                historyEmpty: String(localized: "Nicio vizită notată încă. După o vizită la medic, notează aici la cine, pentru ce și rețeta sau analizele.",
                                     comment: "Empty Istoric pocket of a person's health."),
                peopleEmpty: String(localized: "Nimeni încă. Adaugă medicul de familie sau clinica și ai numărul la îndemână.",
                                    comment: "Empty Oameni pocket of a person's health.")
            )
        case .vet:
            return VisitPocketWords(
                historyEmpty: String(localized: "Nicio vizită notată încă. După o vizită la veterinar, notează aici ce i s-a făcut, la cine și fișa sau rețeta.",
                                     comment: "Empty Istoric pocket of a pet."),
                peopleEmpty: String(localized: "Nimeni încă. Adaugă veterinarul și ai numărul la îndemână.",
                                    comment: "Empty Oameni pocket of a pet.")
            )
        case .note:
            return VisitPocketWords(
                historyEmpty: String(localized: "Nimic notat încă. Notează aici ce observi, cu data: un boboc nou, o mutare la lumină.",
                                     comment: "Empty Istoric pocket of a plant, which takes dated notes."),
                peopleEmpty: String(localized: "Nimeni încă. Adaugă florăria sau grădinarul și ai numărul la îndemână.",
                                    comment: "Empty Oameni pocket of a plant.")
            )
        case .none:
            return VisitPocketWords(
                historyEmpty: String(localized: "Nimic în istoric încă. Aici apare ce rezolvi la termen, cu data și cât a costat.",
                                     comment: "Empty Istoric pocket of a category with no visits (a subscription, a category of one's own without upkeep)."),
                peopleEmpty: String(localized: "Nimeni încă. Adaugă pe cine suni când e nevoie și ai numărul la îndemână.",
                                    comment: "Empty Oameni pocket of a category with no visits (a tenancy, a category of one's own without upkeep).")
            )
        }
    }
}

extension VisitPocketWords {
    /// The words every category had before the kinds, kept with the way back (`VisitShape.formsByKind`).
    static var everyKindBefore: VisitPocketWords {
        VisitPocketWords(
            historyEmpty: String(localized: "Nimic notat încă. Când se face ceva, notează aici: ce, cât a costat și cine a lucrat.", comment: "Empty Istoric pocket."),
            peopleEmpty: String(localized: "Nimeni încă. Adaugă mecanicul, instalatorul sau medicul și îi suni de aici.", comment: "Empty Oameni pocket.")
        )
    }
}
