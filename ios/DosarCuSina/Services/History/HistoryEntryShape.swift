import Foundation

/// What one record's page in Istoric shows and in which words, by the record's kind
/// (`HistoryKind`) laid over its category's visit kind (`VisitShape`), the way `VisitForm` lays
/// a visit's shape over its category: a car's service lists „Ce s-a făcut” and „Service-ul”, a
/// vet's visit „Ce i s-a făcut” and „Veterinarul”, a bill „Ce cuprinde factura” and no stars.
/// A record that closed a deadline reads its deadline's completion instead
/// (`make(completing:visit:)`, by `CompletionRecord`): a policy names „Asigurătorul”, a rovinietă
/// what was bought, a document renewed no one's work, whatever kind the record was stored as.
/// Read by `HistoryEntryScreen`, which holds no words of its own; `docs/COPY_MATRIX.md` shows it
/// for every category (`CopyMatrixTests`).
struct HistoryEntryShape: Equatable {
    /// When the page asks how it went, with its stars.
    enum Rating: Equatable {
        /// A job: always, unless it is a deadline's completion no one did (watering).
        case job
        /// Only when someone did it (an inspection, a vaccine given by a vet).
        case withSomeone
        /// Never: a bill, a purchase, a note.
        case never
    }

    /// Which paper the number printed on it belongs to, said before it.
    enum Reference: Equatable {
        /// „Nr. 0001”.
        case number
        /// „Factura nr. 0001”: a bill, a purchase.
        case invoice
        /// „Polița nr. 0001”.
        case policy
    }

    /// Above the rows of what was done.
    var itemsHeader: String
    /// Above who did it; nil when the record names no one (a note): nothing that makes one
    /// adds a person, so its page has no place for one.
    var providerHeader: String?
    /// Before the number printed on its paper: „Factura nr.” for a bill.
    var reference: Reference
    var rating: Rating
    /// Above the stars, in the kind's words: „Cum a lucrat?”, „Cum a fost?”.
    var ratingHeader: String

    /// Whether its rows are a vehicle's parts („Piesele și prețurile…” when it is deleted).
    var rowsAreParts = false

    /// The page for a record of `kind`, in a category whose visits are `visit`.
    static func make(_ kind: HistoryKind, visit: VisitShape?) -> HistoryEntryShape {
        var shape = base(kind, visit: visit)
        let isJob: Bool = switch kind {
        case .visit, .maintenance, .repair: true
        case .inspection, .purchase, .payment, .vaccination, .treatment, .note: false
        }
        shape.rowsAreParts = isJob && visit?.sum == .parts
        return shape
    }

    /// The page for a record that closed a deadline whose completion is `completion`, in a
    /// category whose visits are `visit`: what the completion is (`CompletionRecord`), never the
    /// kind the record was stored as, so records written before each completion stated its
    /// record read right too. With the way back off (`CompletionRecord.decidesHistoryKind`), the
    /// stored kind's page (`stored`).
    static func make(completing completion: CompletionKind, stored: HistoryKind, visit: VisitShape?) -> HistoryEntryShape {
        guard CompletionRecord.decidesHistoryKind else { return make(stored, visit: visit) }
        switch completion.record {
        case .job:
            return make(.maintenance, visit: visit)
        case .check:
            return make(.inspection, visit: visit)
        case .care, .vaccination:
            return make(completion.record.historyKind, visit: visit)
        case .bill:
            return make(.payment, visit: visit)
        case .purchase:
            return make(.purchase, visit: visit)
        case .atHome:
            // Done at home, or by whoever: never the category's visit provider (a groomer isn't the vet).
            return HistoryEntryShape(itemsHeader: visit?.work?.header ?? HistoryEntryWording.whatWasDone,
                                     providerHeader: HistoryEntryWording.whoGaveIt,
                                     reference: .number, rating: .withSomeone, ratingHeader: HistoryEntryWording.howItWent)
        case .tax:
            return HistoryEntryShape(itemsHeader: HistoryEntryWording.whatWasPaid, providerHeader: HistoryEntryWording.paidTo,
                                     reference: .number, rating: .never, ratingHeader: HistoryEntryWording.howItWent)
        case .policy:
            return HistoryEntryShape(itemsHeader: HistoryEntryWording.whatItCovers, providerHeader: HistoryEntryWording.insurer,
                                     reference: .policy, rating: .never, ratingHeader: HistoryEntryWording.howItWent)
        case .renewal:
            return HistoryEntryShape(itemsHeader: HistoryEntryWording.whatWasDone,
                                     providerHeader: HistoryEntryWording.issuedBy(completion.shape.paper?.gender ?? .masculine),
                                     reference: .number, rating: .never, ratingHeader: HistoryEntryWording.howItWent)
        case .acknowledged:
            return make(.note, visit: visit)
        }
    }

    /// The number printed on its paper, in the words of the paper it is: „Factura nr. 0001”.
    func referenceWords(_ number: String) -> String {
        switch reference {
        case .number: HistoryEntryWording.number(number)
        case .invoice: HistoryEntryWording.invoiceNumber(number)
        case .policy: HistoryEntryWording.policyNumber(number)
        }
    }

    private static func base(_ kind: HistoryKind, visit: VisitShape?) -> HistoryEntryShape {
        let work = visit?.work?.header
        let provider = visit?.provider
        let job = HistoryEntryShape(itemsHeader: work ?? HistoryEntryWording.whatWasDone,
                                    providerHeader: provider?.header ?? HistoryEntryWording.whoWorked,
                                    reference: .number, rating: .job,
                                    ratingHeader: provider?.rating ?? HistoryEntryWording.howItWent)
        switch kind {
        case .visit, .maintenance:
            return job
        case .repair:
            var repair = job
            repair.itemsHeader = work ?? HistoryEntryWording.whatWasRepaired
            return repair
        case .inspection:
            return HistoryEntryShape(itemsHeader: HistoryEntryWording.whatWasChecked, providerHeader: HistoryEntryWording.whoChecked,
                                     reference: .number, rating: .withSomeone, ratingHeader: HistoryEntryWording.howItWent)
        case .vaccination, .treatment:
            return HistoryEntryShape(itemsHeader: work ?? HistoryEntryWording.whatWasDone,
                                     providerHeader: provider?.header ?? HistoryEntryWording.whoGaveIt,
                                     reference: .number, rating: .withSomeone,
                                     ratingHeader: provider?.rating ?? HistoryEntryWording.howItWent)
        case .purchase:
            return HistoryEntryShape(itemsHeader: HistoryEntryWording.whatWasBought, providerHeader: HistoryEntryWording.boughtFrom,
                                     reference: .invoice, rating: .never, ratingHeader: HistoryEntryWording.howItWent)
        case .payment:
            return HistoryEntryShape(itemsHeader: HistoryEntryWording.whatTheBillHolds, providerHeader: HistoryEntryWording.paidTo,
                                     reference: .invoice, rating: .never, ratingHeader: HistoryEntryWording.howItWent)
        case .note:
            return HistoryEntryShape(itemsHeader: HistoryEntryWording.whatWasNoted, providerHeader: nil,
                                     reference: .number, rating: .never, ratingHeader: HistoryEntryWording.howItWent)
        }
    }

    /// Whether the page asks how it went: `isCompletion` when the record closed a deadline,
    /// `hasSomeone` when it names who did it.
    func asksRating(isCompletion: Bool, hasSomeone: Bool) -> Bool {
        switch rating {
        case .job: hasSomeone || !isCompletion
        case .withSomeone: hasSomeone
        case .never: false
        }
    }
}

/// The words a record's page in Istoric says: its kind's (`HistoryEntryShape`) and every kind's.
enum HistoryEntryWording {
    static var whatWasDone: String { String(localized: "Ce s-a făcut", comment: "Header: the jobs and parts of a visit.") }
    static var whatWasRepaired: String { String(localized: "Ce s-a reparat", comment: "Istoric record: what was repaired.") }
    static var whatWasChecked: String { String(localized: "Ce s-a verificat", comment: "Istoric record: what an inspection checked.") }
    static var whatWasBought: String { String(localized: "Ce ai cumpărat", comment: "Istoric record: what was bought.") }
    static var whatTheBillHolds: String { String(localized: "Ce cuprinde", comment: "Istoric record: the lines of a bill or a payment.") }
    static var whoWorked: String { String(localized: "Cine a lucrat", comment: "Header: who did the job.") }
    static var whoChecked: String { String(localized: "Cine a verificat", comment: "Istoric record: who did an inspection.") }
    static var whoGaveIt: String { String(localized: "Cine s-a ocupat", comment: "Istoric record: who gave a vaccine or a treatment.") }
    static var boughtFrom: String { String(localized: "De unde", comment: "Istoric record: where something was bought.") }
    static var paidTo: String { String(localized: "Cui ai plătit", comment: "Istoric record: who a payment went to.") }
    static var whatWasPaid: String { String(localized: "Ce ai plătit", comment: "Istoric record: what a tax or a declaration paid for.") }
    static var whatItCovers: String { String(localized: "Ce acoperă", comment: "Istoric record: what a renewed insurance policy covers.") }
    static var insurer: String { String(localized: "Asigurătorul", comment: "Istoric record: who a renewed insurance policy is with.") }
    /// Who issued a renewed paper, agreeing with its noun: „Cine l-a emis” for „Actul nou”.
    static func issuedBy(_ gender: CompletionShape.Paper.Gender) -> String {
        switch gender {
        case .masculine: String(localized: "Cine l-a emis", comment: "Istoric record: who issued a renewed paper named by a masculine noun (a document, a card, a contract).")
        case .feminine: String(localized: "Cine a emis-o", comment: "Istoric record: who issued a renewed paper named by a feminine noun.")
        case .plural: String(localized: "Cine le-a emis", comment: "Istoric record: who issued renewed papers named by a plural noun.")
        }
    }
    static var whatWasNoted: String { String(localized: "Ce ai notat", comment: "Istoric record: the rows of a note.") }
    static var howItWent: String { String(localized: "Cum a fost") }
    static var ratingFootnote: String { String(localized: "Nota intră în stelele celui care a lucrat.", comment: "Footnote under a job rating.") }
    static var notes: String { String(localized: "Note", comment: "Header: notes.") }
    static var changeNote: String { String(localized: "Schimbă nota") }
    static var addNote: String { String(localized: "Adaugă o notă") }
    static var delete: String { String(localized: "Șterge din istoric") }
    static var confirmDelete: String { String(localized: "Șterge", comment: "Confirm deleting.") }
    static var keep: String { String(localized: "Păstrează", comment: "Cancel a delete.") }

    static func invoiceNumber(_ reference: String) -> String {
        String(localized: "Factura nr. \(reference)", comment: "A bill's invoice number on its history page.")
    }

    static func policyNumber(_ reference: String) -> String {
        String(localized: "Polița nr. \(reference)", comment: "A renewed insurance policy's number on its history page.")
    }

    static func number(_ reference: String) -> String {
        String(localized: "Nr. \(reference)", comment: "The number of the paper a history entry records.")
    }

    static func deleteQuestion(_ title: String) -> String {
        String(localized: "Ștergi „\(title)” din istoric?", comment: "Delete confirmation for a history entry.")
    }

    static func reopens(on day: String) -> String {
        String(localized: "Termenul revine la \(day), ca și cum nu l-ai fi rezolvat.", comment: "Deleting the latest completion moves its deadline back to the day it was due.")
    }

    static var keepsDeadline: String {
        String(localized: "Termenul rămâne cum e acum.", comment: "Deleting an older completion leaves its deadline alone.")
    }

    /// Deleting a record that closed no deadline: its rows go.
    static func removesRows(parts: Bool) -> String {
        parts
            ? String(localized: "Piesele și prețurile notate aici se șterg de pe acest telefon.", comment: "Delete confirmation for a history entry.")
            : String(localized: "Ce ai notat aici se șterge de pe acest telefon.", comment: "Delete confirmation for a history entry that lists no vehicle parts.")
    }

    static func removesReading(_ reading: String) -> String {
        String(localized: "Se șterge și citirea de \(reading) notată aici.", comment: "Deleting a history entry also removes the counter reading it recorded, such as '45.724 km'.")
    }

    static var keepsDocuments: String {
        String(localized: "Ce ai atașat rămâne în dosar.", comment: "Deleting a history entry keeps the documents filed with it.")
    }
}
