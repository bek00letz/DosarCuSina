import SwiftData
import SwiftUI

/// The one way into completing a deadline inside the app, the same from its page and from
/// Urmează's row (the swipe, the menu, VoiceOver's action): what it is called and what it does
/// are the kind's (`CompletionShape`). A chore is done at once ("Gata"), with the toast that
/// takes it back or adds a note; any other kind opens "Am rezolvat" (`ObligationCompleteSheet`),
/// which asks what the kind asks: the day, the cost, the paper. From outside the app (reminder
/// buttons, the widget, Siri) a deadline is closed by `IntentEngine.perform` instead.
///
/// Every start carries the cycle the person saw (the due day on the row or the page), as
/// `IntentEngine` does: a second activation (VoiceOver twice, a swipe and the menu) or a sheet
/// left open while a reminder closed the cycle files nothing against the next one
/// (`ObligationActionError.cycleClosed`, thrown by `ObligationActions.complete`).
@MainActor
struct CompletionEntry {
    let context: ModelContext

    /// What starting it did.
    enum Start {
        /// Done in one tap: the toast to show, with its undo.
        case done(DSToast)
        /// "Am rezolvat" to open, for the screen's `completionSheet`.
        case asks(CompletionRequest)
    }

    /// Starts completing `obligation` at `cycle`, the due day the person saw, the way its kind
    /// says. A chore's toast offers "Adaugă o notă", which hands `addNote` the completion's
    /// entry and the toast. Throws `cycleClosed` when that cycle was closed meanwhile.
    func start(_ obligation: Obligation, cycle: CalendarDay, addNote: @escaping @MainActor (UUID, DSToast) -> Void) throws -> Start {
        guard obligation.completion(in: context).isOneTap else {
            try ObligationActions(context: context).requireOpen(obligation, cycle: cycle)
            return .asks(CompletionRequest(obligationID: obligation.id, cycle: cycle))
        }
        return .done(try UpcomingActions(context: context).complete(obligation, title: obligation.title, cycle: cycle, addNote: addNote))
    }
}

/// "Am rezolvat" waiting to open for one deadline, at the cycle the person saw.
struct CompletionRequest: Identifiable, Equatable {
    let obligationID: UUID
    /// The due day the person saw when they asked: the sheet files only against it.
    let cycle: CalendarDay
    var id: UUID { obligationID }
}

extension View {
    /// Opens "Am rezolvat" for the request `CompletionEntry.start` gave; what it saved is said
    /// by its toast, in `toast`.
    func completionSheet(_ request: Binding<CompletionRequest?>, toast: Binding<DSToast?>) -> some View {
        modifier(CompletionSheetModifier(request: request, toast: toast))
    }
}

private struct CompletionSheetModifier: ViewModifier {
    @Binding var request: CompletionRequest?
    @Binding var toast: DSToast?
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content.dsSheet(item: $request) { request in
            if let obligation = UpcomingActions(context: context).obligation(request.obligationID) {
                ObligationCompleteSheet(obligation: obligation, cycle: request.cycle) { result in
                    self.request = nil
                    if let result { toast = result }
                }
            }
        }
    }
}

/// "Am rezolvat" opened from outside the app (`AppRoute.completion`): a reminder's or Siri's
/// „Am rezolvat” on a deadline whose closing asks what only the app can ask, a new day or a new
/// document (`CompletionShape.closesOutsideTheApp`). The same sheet as the page's, for the cycle
/// the person saw, behind its section's lock (Face ID for a locked category); what it saved is
/// said on the shell's toast, over the deadline's page.
struct OutsideCompletionSheet: View {
    let cycle: CalendarDay

    @Query private var matches: [Obligation]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.announce) private var announce

    init(obligationID: UUID, cycle: CalendarDay) {
        self.cycle = cycle
        _matches = Query(filter: #Predicate<Obligation> { $0.id == obligationID })
    }

    var body: some View {
        if let obligation = matches.first {
            if let assetID = obligation.asset?.id {
                SectionIDLockGate(assetID: assetID, inSheet: true) { sheet(obligation) }
            } else {
                // A deadline of the whole household has no section, so no lock.
                sheet(obligation)
            }
        } else {
            DSEmptyState("Termenul nu mai există", systemImage: "calendar.badge.exclamationmark", message: "Poate a fost șters împreună cu secțiunea lui.")
        }
    }

    private func sheet(_ obligation: Obligation) -> some View {
        ObligationCompleteSheet(obligation: obligation, cycle: cycle) { result in
            if let result { announce(result) }
            dismiss()
        }
    }
}
