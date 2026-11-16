import Foundation

/// What one record's page in Istoric shows and in which words, by the record's kind
/// (`HistoryKind`) laid over its category's visit kind (`VisitShape`), the way `VisitForm` lays
/// a visit's shape over its category: a car's service lists „Ce s-a făcut” and „Service-ul”, a
/// vet's visit „Ce i s-a făcut” and „Veterinarul”, a bill „Ce cuprinde factura” and no stars.
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

    /// Above the rows of what was done.
    var itemsHeader: String
    /// Above who did it.
    var providerHeader: String
    /// Before the number printed on its paper: „Factura nr.” for a bill.
    var referenceIsInvoice: Bool
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

    private static func base(_ kind: HistoryKind, visit: VisitShape?) -> HistoryEntryShape {
        let work = visit?.work?.header
        let provider = visit?.provider
        let job = HistoryEntryShape(itemsHeader: work ?? HistoryEntryWording.whatWasDone,
                                    providerHeader: provider?.header ?? HistoryEntryWording.whoWorked,
                                    referenceIsInvoice: false, rating: .job,
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
                                     referenceIsInvoice: false, rating: .withSomeone, ratingHeader: HistoryEntryWording.howItWent)
        case .vaccination, .treatment:
            return HistoryEntryShape(itemsHeader: work ?? HistoryEntryWording.whatWasDone,
                                     providerHeader: provider?.header ?? HistoryEntryWording.whoGaveIt,
                                     referenceIsInvoice: false, rating: .withSomeone,
                                     ratingHeader: provider?.rating ?? HistoryEntryWording.howItWent)
        case .purchase:
            return HistoryEntryShape(itemsHeader: HistoryEntryWording.whatWasBought, providerHeader: HistoryEntryWording.boughtFrom,
                                     referenceIsInvoice: true, rating: .never, ratingHeader: HistoryEntryWording.howItWent)
        case .payment:
            return HistoryEntryShape(itemsHeader: HistoryEntryWording.whatTheBillHolds, providerHeader: HistoryEntryWording.paidTo,
                                     referenceIsInvoice: true, rating: .never, ratingHeader: HistoryEntryWording.howItWent)
        case .note:
            return HistoryEntryShape(itemsHeader: HistoryEntryWording.whatWasDone, providerHeader: HistoryEntryWording.whoWorked,
                                     referenceIsInvoice: false, rating: .never, ratingHeader: HistoryEntryWording.howItWent)
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
