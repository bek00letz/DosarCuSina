import SwiftData
import SwiftUI

/// Done, snooze and their undo, as the Urmează list and the obligation page
/// use them. Every change goes through `ObligationActions`; this only adds the
/// toast wording and the undo closure.
@MainActor
struct UpcomingActions {
    let context: ModelContext
    var calendar: Calendar = .current

    /// Snooze lengths offered, in days.
    static let snoozeChoices: [Int] = [1, 3, 7, 14]

    /// "Mâine", "Peste 3 zile", "Peste 14 zile": a length the person picks, worded
    /// like a reminder's lead.
    static func snoozeTitle(days: Int) -> String {
        days == 1
            ? String(localized: "Mâine", comment: "Snooze until tomorrow")
            : String(localized: "Peste \(DurationWording.lead(days: days))", comment: "Snooze for a length such as '3 zile' or '14 zile'")
    }

    func obligation(_ id: UUID) -> Obligation? {
        var descriptor = FetchDescriptor<Obligation>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Completes and returns the toast with its undo.
    func complete(_ obligation: Obligation, title: String, cost: Money? = nil, on date: Date? = nil) throws -> DSToast {
        let actions = ObligationActions(context: context, calendar: calendar)
        let done = try actions.complete(obligation, on: date, cost: cost)
        let message: LocalizedStringResource
        if obligation.status == .active {
            let next = DosarFormat.longDay(obligation.dueDay(in: calendar))
            message = "\(title): gata. Următorul termen e pe \(next)."
        } else {
            message = "\(title): gata."
        }
        return .undo(message, receipt: done.receipt)
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
