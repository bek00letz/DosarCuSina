import SwiftData
import SwiftUI

/// The one way into completing a deadline inside the app, the same from its page and from
/// Urmează's row (the swipe, the menu, VoiceOver's action): what it is called and what it does
/// are the kind's (`CompletionShape`). A chore is done at once ("Gata"), with the toast that
/// takes it back or adds a note; any other kind opens "Am rezolvat" (`ObligationCompleteSheet`),
/// which asks what the kind asks: the day, the cost, the paper. From outside the app (reminder
/// buttons, the widget, Siri) a deadline is closed by `IntentEngine.perform` instead.
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

    /// Starts completing `obligation` the way its kind says. A chore's toast offers
    /// "Adaugă o notă", which hands `addNote` the completion's entry and the toast.
    func start(_ obligation: Obligation, addNote: @escaping @MainActor (UUID, DSToast) -> Void) throws -> Start {
        guard obligation.kind.completion.isOneTap else {
            return .asks(CompletionRequest(obligationID: obligation.id))
        }
        return .done(try UpcomingActions(context: context).complete(obligation, title: obligation.title, addNote: addNote))
    }
}

/// "Am rezolvat" waiting to open for one deadline.
struct CompletionRequest: Identifiable, Equatable {
    let obligationID: UUID
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
        content.sheet(item: $request) { request in
            if let obligation = UpcomingActions(context: context).obligation(request.obligationID) {
                ObligationCompleteSheet(obligation: obligation) { result in
                    self.request = nil
                    if let result { toast = result }
                }
            }
        }
    }
}
