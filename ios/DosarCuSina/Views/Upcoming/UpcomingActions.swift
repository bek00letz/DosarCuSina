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

    static func snoozeTitle(days: Int) -> String {
        switch days {
        case 1: return String(localized: "Mâine")
        case 7: return String(localized: "Peste o săptămână")
        case 14: return String(localized: "Peste două săptămâni")
        default: return String(localized: "Peste \(DayCount.phrase(days))")
        }
    }

    func obligation(_ id: UUID) -> Obligation? {
        var descriptor = FetchDescriptor<Obligation>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Completes and returns the toast with its undo.
    func complete(_ obligation: Obligation, title: String, cost: Money? = nil, on date: Date? = nil) throws -> (entry: HistoryEntry, toast: DSToast) {
        let actions = ObligationActions(context: context, calendar: calendar)
        let entry = try actions.complete(obligation, on: date, cost: cost)
        let message: LocalizedStringResource
        if obligation.status == .active {
            let next = obligation.dueDay(in: calendar).startDate(in: calendar).formatted(.dateTime.day().month(.wide).year().locale(.dosarDefault))
            message = "\(title): gata. Următorul termen e pe \(next)."
        } else {
            message = "\(title): gata."
        }
        let toast = DSToast.undo(message) {
            try? ObligationActions(context: context, calendar: calendar).undo(entry)
        }
        return (entry, toast)
    }

    func snooze(_ obligation: Obligation, days: Int, title: String) throws -> DSToast {
        try ObligationActions(context: context, calendar: calendar).snooze(obligation, days: days)
        let phrase = Self.snoozeTitle(days: days).lowercased()
        var toast = DSToast.undo("Am amânat \(title). Îți amintesc \(phrase).") {
            try? ObligationActions(context: context, calendar: calendar).clearSnooze(obligation)
        }
        toast.systemImage = "clock.arrow.circlepath"
        toast.tint = DS.Palette.accent
        toast.feedback = .impact(weight: .light)
        return toast
    }

    static func failureToast(_ error: Error) -> DSToast {
        DSToast(
            title: "\(error.localizedDescription)",
            systemImage: "exclamationmark.circle.fill",
            tint: DSStatus.overdue.color,
            actionTitle: nil,
            action: nil,
            feedback: .error
        )
    }
}
