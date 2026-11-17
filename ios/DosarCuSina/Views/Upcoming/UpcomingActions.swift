import SwiftData
import SwiftUI

/// Done, snooze and their undo, as the Urmează list and the obligation page
/// use them. Every change goes through `ObligationActions`; this only adds the
/// toast wording and the undo closure.
@MainActor
struct UpcomingActions {
    let context: ModelContext
    var calendar: Calendar = .dosar

    /// Snooze lengths offered, in days.
    static let snoozeChoices: [Int] = [1, 3, 7, 14]

    /// "Mâine", "Peste 3 zile", "Peste 14 zile": a length the person picks, in days, by the
    /// String Catalog's plural variations (one day is "Mâine").
    static func snoozeTitle(days: Int) -> String {
        String(localized: "Peste \(days) zile", comment: "Snooze for a number of days, with Romanian plural forms: one „Mâine”, „Peste 3 zile”, „Peste 20 de zile”.")
    }

    func obligation(_ id: UUID) -> Obligation? {
        var descriptor = FetchDescriptor<Obligation>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Completes today in one step and returns the toast with its undo. When the deadline's
    /// kind asks nothing (a chore, `CompletionShape.offersNoteAfter`) and the screen can show
    /// the note sheet, the toast also offers "Adaugă o notă", which hands `addNote` the
    /// completion's entry in Istoric and the toast, to show again if no note is saved.
    func complete(_ obligation: Obligation, title: String, addNote: (@MainActor (UUID, DSToast) -> Void)? = nil) throws -> DSToast {
        let actions = ObligationActions(context: context, calendar: calendar)
        let done = try actions.complete(obligation)
        let message: LocalizedStringResource
        if obligation.status == .active {
            let next = DosarFormat.longDay(obligation.dueDay)
            message = "\(title): gata. Următorul termen e pe \(next)."
        } else {
            message = "\(title): gata."
        }
        var toast = DSToast.undo(message, receipt: done.receipt)
        if obligation.completion(in: context).offersNoteAfter, let addNote {
            let entryID = done.value.id
            toast.offer = DSToast.Offer(title: Text("Adaugă o notă", comment: "Toast after a chore's Gata: opens a note for that completion.")) { shown in
                addNote(entryID, shown)
            }
            toast.duration = DSToast.offerDuration
        }
        return toast
    }

    func snooze(_ obligation: Obligation, days: Int, title: String) throws -> DSToast {
        let receipt = try ObligationActions(context: context, calendar: calendar).snooze(obligation, days: days)
        let phrase = Self.snoozeTitle(days: days).lowercased()
        var toast = DSToast.undo("Am amânat \(title). Îți amintesc \(phrase).", receipt: receipt)
        toast.systemImage = "clock.arrow.circlepath"
        toast.tint = DS.Palette.accent
        toast.feedback = .impact(weight: .light)
        return toast
    }

    static func failureToast(_ error: Error) -> DSToast {
        .failure(error)
    }
}
