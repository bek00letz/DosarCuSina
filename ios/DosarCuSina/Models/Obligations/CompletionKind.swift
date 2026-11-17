import Foundation

/// What closing one deadline asks, stated by every blueprint (`ObligationBlueprint.completion`,
/// with no default: the compiler refuses a blueprint that forgets) and described once here
/// (`shape`): a chore is one tap, an ITP asks its fee and the ITP report, a renewed document the
/// new one and its expiry, a bill what was paid. A deadline of one's own takes it from its
/// importance (`own(_:)`, by the kind `DeadlineChoice` gave it). `docs/COPY_MATRIX.md` shows
/// every category's deadlines in these words (`CopyMatrixTests`).
///
/// Raw values are part of the `.dosar` contract (a blueprint's `completion`).
public enum CompletionKind: String, Codable, Sendable, CaseIterable {
    /// A chore: done today in one tap, a note offered after. Watering, cleaning the chain.
    case chore
    /// An end that only needs knowing: done in one tap. A warranty's, a minimum term's.
    case acknowledged
    /// A car's service: the cost, the service's invoice, the kilometres.
    case vehicleService
    /// Changing a car's tyres: the cost, the tyre shop's invoice, the kilometres.
    case tyreChange
    /// A bike's service: the cost, the shop's invoice if it went to one, the kilometres.
    case bikeService
    /// A chimney swept: the cost, the firm's invoice.
    case chimneySweep
    /// Upkeep done at home (descaling, a new filter, deworming): the day and what it cost; the
    /// counter only where the deadline counts on it.
    case doneAtHome
    /// The periodic service of a category of one's own: the cost, the invoice, its counter.
    case ownService
    /// A bill paid: what was paid and the bill, filed as a bill.
    case bill
    /// The building tax: what was paid and the receipt.
    case buildingTax
    /// The rental income declaration: what was paid and the filing's receipt.
    case rentalDeclaration
    /// A tax of one's own: what was paid and the receipt.
    case ownTax
    /// Something renewed with a new end (a renewal of one's own): the new paper and when it
    /// expires, the deadline going on from that day.
    case newDocument
    /// A personal document (an identity card, a passport, a licence) renewed: a new one has
    /// another series and number, so it is a document of its own, added on its own. Closing asks
    /// no new expiry: the deadline closes, the old one shows as expired, and its page offers the
    /// new one and deleting the old one (`CompletionShape.Replacement`).
    case documentReplaced
    /// The European health card renewed: the new card and when it expires.
    case newHealthCard
    /// A subscription's contract renewed: the new contract and when it ends.
    case newContract
    /// A tenancy renewed: the new contract and when it ends.
    case newLease
    /// An insurance renewed: the price and the new policy.
    case policy
    /// A car's ITP: the fee and the ITP report.
    case itp
    /// The rovinietă: the price and the rovinietă.
    case vignette
    /// A car's first-aid kit and extinguisher: the price and the day the new ones expire.
    case safetyKit
    /// A boiler's check: the fee and the report.
    case boilerCheck
    /// A gas installation's check or revision: the fee and the report.
    case gasCheck
    /// A legal deadline of one's own: the fee and the proof.
    case ownLegal
    /// A pet's vaccine: the cost and the pet's health booklet.
    case petVaccine
    /// Yearly tests: the cost, the results and what the doctor said.
    case checkup
    /// A dentist's check-up: the cost and what was done.
    case dentist
    /// A person's vaccine: the cost and the vaccination certificate.
    case vaccine
    /// A health deadline of one's own: the cost, the result and a note.
    case ownHealth

    /// A deadline with no blueprint (one of the person's own, from "Termen nou") by its kind,
    /// which its importance gave it (`DeadlineChoice.Importance.kind`). The kinds the answers
    /// don't give (a deadline from an older backup) are read the same way, each named here.
    public static func own(_ kind: ObligationKind) -> CompletionKind {
        switch kind {
        case .routine: .chore
        case .legal: .ownLegal
        case .payment: .bill
        case .health: .ownHealth
        case .tax: .ownTax
        case .insurance: .policy
        case .renewal: .newDocument
        case .maintenance: .ownService
        }
    }

    /// A stored `completion`: nil when it is missing (a blueprint from before blueprints stated
    /// one) or from a newer version; the deadline then completes as one of the person's own
    /// (`own(_:)`).
    init?(stored raw: String?) {
        guard let raw, let kind = CompletionKind(rawValue: raw) else { return nil }
        self = kind
    }

    /// What completing asks, and every word of it but those all kinds share
    /// (`CompletionWording`).
    public var shape: CompletionShape {
        switch self {
        case .chore, .acknowledged:
            return .oneTap
        case .vehicleService:
            return CompletionShape(cost: .cost, paper: Self.invoice(String(localized: "De la service-ul care a lucrat.", comment: "Am rezolvat: which invoice, for a car's service.")),
                                   counter: .section)
        case .tyreChange:
            return CompletionShape(cost: .cost, paper: Self.invoice(String(localized: "De la vulcanizare.", comment: "Am rezolvat: which invoice, for a tyre change.")),
                                   counter: .section)
        case .bikeService:
            return CompletionShape(cost: .cost, paper: Self.invoice(String(localized: "De la service, dacă ai dus-o acolo.", comment: "Am rezolvat: which invoice, for a bike's service.")),
                                   counter: .section)
        case .chimneySweep:
            return CompletionShape(cost: .cost, paper: Self.invoice(String(localized: "De la firma care a curățat coșul.", comment: "Am rezolvat: which invoice, for a chimney sweep.")))
        case .doneAtHome:
            return CompletionShape(cost: .cost, counter: .countedOn)
        case .ownService:
            return CompletionShape(cost: .cost, paper: Self.invoice(String(localized: "De la cel care a lucrat.", comment: "Am rezolvat: which invoice, for a service of one's own.")),
                                   counter: .section)
        case .bill:
            return CompletionShape(cost: .paid, paper: CompletionShape.Paper(
                name: String(localized: "Factura"), gender: .feminine, use: .logged,
                action: String(localized: "Fotografiază factura"),
                example: String(localized: "Cea pe care ai plătit-o.")))
        case .buildingTax, .ownTax:
            return CompletionShape(cost: .paid, paper: CompletionShape.Paper(
                name: String(localized: "Chitanța"), gender: .feminine, use: .keep,
                action: String(localized: "Fotografiază chitanța"),
                example: String(localized: "Sau dovada plății din aplicația băncii.")))
        case .rentalDeclaration:
            return CompletionShape(cost: .paid, paper: CompletionShape.Paper(
                name: String(localized: "Recipisa", comment: "Am rezolvat: the receipt of a filed tax declaration."), gender: .feminine, use: .keep,
                action: String(localized: "Fotografiază recipisa", comment: "Am rezolvat: photographs the receipt of a filed tax declaration."),
                example: String(localized: "Dovada că ai depus declarația, din Spațiul Privat Virtual.", comment: "Am rezolvat: which paper, for the rental income declaration.")))
        case .newDocument:
            return CompletionShape(paper: CompletionShape.Paper(
                name: String(localized: "Actul nou"), gender: .masculine, use: .expiry,
                action: String(localized: "Fotografiază actul nou"),
                example: String(localized: "Partea cu data la care expiră.")), newEnd: .expires)
        case .documentReplaced:
            return CompletionShape(cost: .cost, replacement: CompletionShape.Replacement(
                inSheet: String(localized: "Închid termenul și trec actul acesta ca expirat. Actul nou are altă serie și alt număr, așa că îl adaugi separat, cu poza lui.",
                                comment: "Am rezolvat on a personal document: what saving does, and that the new document is added on its own."),
                title: String(localized: "Ai reînnoit actul", comment: "A renewed personal document's page: the card that offers the new one."),
                message: String(localized: "Cel nou are altă serie și alt număr: adaugă-l ca act nou, cu poza lui. Pe acesta îl poți păstra sau șterge.",
                                comment: "A renewed personal document's page: why the new one is added on its own."),
                add: String(localized: "Adaugă actul nou", comment: "A renewed personal document's page: adds the new document for the same person."),
                delete: String(localized: "Șterge actul vechi", comment: "A renewed personal document's page: deletes the old document."),
                open: String(localized: "Vezi actul", comment: "Toast after closing a personal document's renewal: opens the document's page.")))
        case .newHealthCard:
            return CompletionShape(paper: CompletionShape.Paper(
                name: String(localized: "Cardul nou", comment: "Am rezolvat: the new European health card."), gender: .masculine, use: .expiry,
                action: String(localized: "Fotografiază cardul nou", comment: "Am rezolvat: photographs the new European health card."),
                example: String(localized: "Fața, cu data la care expiră.", comment: "Am rezolvat: which side of the health card.")), newEnd: .expires)
        case .newContract:
            return CompletionShape(paper: Self.contract(String(localized: "Pagina cu perioada contractului.", comment: "Am rezolvat: which page of a subscription's new contract.")),
                                   newEnd: .ends)
        case .newLease:
            return CompletionShape(paper: Self.contract(String(localized: "Pagina cu perioada închirierii.", comment: "Am rezolvat: which page of a new tenancy contract.")),
                                   newEnd: .ends)
        case .policy:
            return CompletionShape(cost: .cost, paper: CompletionShape.Paper(
                name: String(localized: "Polița nouă"), gender: .feminine, use: .nextDate,
                action: String(localized: "Fotografiază polița nouă", comment: "Am rezolvat: photographs the new insurance policy."),
                example: String(localized: "Cea primită de la asigurător sau de la broker.", comment: "Am rezolvat: which paper, for a renewed insurance.")))
        case .itp:
            return CompletionShape(cost: .cost, paper: CompletionShape.Paper(
                name: String(localized: "Raportul ITP", comment: "Am rezolvat: the ITP inspection report."), gender: .masculine, use: .nextDate,
                action: String(localized: "Fotografiază raportul ITP", comment: "Am rezolvat: photographs the ITP inspection report."),
                example: String(localized: "Cel primit la stație, cu data următoarei inspecții.", comment: "Am rezolvat: which paper, for an ITP.")))
        case .vignette:
            return CompletionShape(cost: .cost, paper: CompletionShape.Paper(
                name: String(localized: "Rovinieta", comment: "Am rezolvat: the road vignette's receipt."), gender: .feminine, use: .nextDate,
                action: String(localized: "Fotografiază rovinieta", comment: "Am rezolvat: photographs the road vignette's receipt."),
                example: String(localized: "Chitanța sau confirmarea primită pe e-mail.", comment: "Am rezolvat: which paper, for a road vignette.")))
        case .safetyKit:
            return CompletionShape(cost: .cost, newEnd: .expires)
        case .boilerCheck:
            return CompletionShape(cost: .cost, paper: Self.report(String(localized: "De la firma autorizată ISCIR care a verificat centrala.", comment: "Am rezolvat: which report, for a boiler check.")))
        case .gasCheck:
            return CompletionShape(cost: .cost, paper: Self.report(String(localized: "De la firma autorizată care a verificat instalația.", comment: "Am rezolvat: which report, for a gas installation check.")))
        case .ownLegal:
            return CompletionShape(cost: .cost, paper: CompletionShape.Paper(
                name: String(localized: "Dovada"), gender: .feminine, use: .nextDate,
                action: String(localized: "Fotografiază dovada"),
                example: String(localized: "Raportul, certificatul sau chitanța.")))
        case .petVaccine:
            return CompletionShape(cost: .cost, paper: CompletionShape.Paper(
                name: String(localized: "Carnetul de sănătate", comment: "Am rezolvat: a pet's health booklet."), gender: .masculine, use: .nextDate,
                action: String(localized: "Fotografiază carnetul", comment: "Am rezolvat: photographs a pet's health booklet."),
                example: String(localized: "Pagina cu vaccinul și data rapelului.", comment: "Am rezolvat: which page of a pet's health booklet.")))
        case .checkup:
            return CompletionShape(cost: .cost, paper: CompletionShape.Paper(
                name: String(localized: "Rezultatele", comment: "Am rezolvat: the results of yearly tests."), gender: .plural, use: .keep,
                action: String(localized: "Fotografiază rezultatele", comment: "Am rezolvat: photographs the results of yearly tests."),
                example: String(localized: "Buletinul de analize, de la laborator.", comment: "Am rezolvat: which paper, for yearly tests.")),
                                   note: CompletionShape.Note(prompt: String(localized: "Ce a spus medicul, ce urmează.", comment: "Am rezolvat: the note's example, after tests.")))
        case .dentist:
            return CompletionShape(cost: .cost, note: CompletionShape.Note(prompt: Self.whatWasDone))
        case .vaccine:
            return CompletionShape(cost: .cost, paper: CompletionShape.Paper(
                name: String(localized: "Adeverința de vaccinare", comment: "Am rezolvat: a person's vaccination certificate."), gender: .feminine, use: .keep,
                action: String(localized: "Fotografiază adeverința", comment: "Am rezolvat: photographs a vaccination certificate."),
                example: String(localized: "Sau pagina din carnetul de vaccinări.", comment: "Am rezolvat: which paper, for a person's vaccine.")))
        case .ownHealth:
            return CompletionShape(cost: .cost, paper: CompletionShape.Paper(
                name: String(localized: "Rezultatul"), gender: .masculine, use: .keep,
                action: String(localized: "Fotografiază rezultatul"),
                example: String(localized: "Analizele, rețeta sau carnetul de vaccinări.")),
                                   note: CompletionShape.Note(prompt: Self.whatWasDone))
        }
    }

    // MARK: Papers several kinds share, each with its own example

    private static func invoice(_ example: String) -> CompletionShape.Paper {
        CompletionShape.Paper(name: String(localized: "Factura"), gender: .feminine, use: .history,
                              action: String(localized: "Fotografiază factura"), example: example)
    }

    private static func contract(_ example: String) -> CompletionShape.Paper {
        CompletionShape.Paper(name: String(localized: "Contractul nou", comment: "Am rezolvat: a renewed contract."), gender: .masculine, use: .end,
                              action: String(localized: "Fotografiază contractul nou", comment: "Am rezolvat: photographs a renewed contract."), example: example,
                              origin: .signed)
    }

    private static func report(_ example: String) -> CompletionShape.Paper {
        CompletionShape.Paper(name: String(localized: "Procesul-verbal", comment: "Am rezolvat: the report a check leaves."), gender: .masculine, use: .nextDate,
                              action: String(localized: "Fotografiază procesul-verbal", comment: "Am rezolvat: photographs a check's report."), example: example)
    }

    private static var whatWasDone: String {
        String(localized: "Ce s-a făcut, ce urmează.")
    }
}

/// What a completion is, as Istoric keeps it and shows it: a job someone did, upkeep done at
/// home, a check, care from a doctor, a vaccine, a bill, a tax, a policy, something bought, a
/// renewal, or an end only noted. Every completion kind states one
/// (`CompletionKind.record`, with no default), so the history kind a completion writes
/// (`historyKind`) and the words its page says in Istoric (`HistoryEntryShape.make(completing:visit:)`)
/// come from the deadline's declared completion, never from its importance.
public enum CompletionRecord: String, Sendable, CaseIterable {
    /// Work someone did on it: a car's service, a tyre change, a chimney swept.
    case job
    /// Upkeep done at home, or a chore: deworming, descaling, watering.
    case atHome
    /// A check that leaves a report: an ITP, a boiler's or a gas installation's.
    case check
    /// Care from a doctor: yearly tests, a dentist.
    case care
    /// A vaccine, a person's or a pet's.
    case vaccination
    /// A bill paid.
    case bill
    /// A tax or a declaration paid.
    case tax
    /// An insurance policy renewed.
    case policy
    /// Something bought: a rovinietă, a new first-aid kit.
    case purchase
    /// A document, a card or a contract renewed.
    case renewal
    /// An end that was only noted: a warranty's, a minimum term's.
    case acknowledged

    /// The history kind its record is stored as (part of the `.dosar` contract).
    public var historyKind: HistoryKind {
        switch self {
        case .job, .atHome: .maintenance
        case .check: .inspection
        case .care: .treatment
        case .vaccination: .vaccination
        case .bill, .tax, .policy: .payment
        case .purchase: .purchase
        case .renewal, .acknowledged: .note
        }
    }

    /// The way back: off, a completion is stored as its deadline's importance gave it before
    /// (`HistoryKind.byImportance`) and its page reads that kind alone. Remove with the owner's OK.
    public static let decidesHistoryKind = true
}

extension CompletionKind {
    /// What its completion is in Istoric.
    public var record: CompletionRecord {
        switch self {
        case .chore, .doneAtHome: .atHome
        case .acknowledged: .acknowledged
        case .vehicleService, .tyreChange, .bikeService, .chimneySweep, .ownService: .job
        case .bill: .bill
        case .buildingTax, .rentalDeclaration, .ownTax: .tax
        case .newDocument, .documentReplaced, .newHealthCard, .newContract, .newLease: .renewal
        case .policy: .policy
        // A legal deadline of one's own reads as a check, a health one as care, as before.
        case .itp, .boilerCheck, .gasCheck, .ownLegal: .check
        case .vignette, .safetyKit: .purchase
        case .petVaccine, .vaccine: .vaccination
        case .checkup, .dentist, .ownHealth: .care
        }
    }
}
