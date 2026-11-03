import Foundation
import SwiftData

/// A subscription's "Factura de plătit" follows how its bills are paid. When the bank
/// starts paying by direct debit, the reminder already made pauses: nothing to pay by
/// hand. When direct debit stops, a reminder whose day hasn't passed comes back, and one
/// whose day has passed stays paused until the next bill takes it up again
/// (`CaptureFilingPlan.existingDeadline`). Bills keep going into the history either way,
/// so the note about a bill that hasn't come still works.
///
/// Run by `AssetActions.update`, the one path that changes a section's values; the
/// deadline changes go through `ObligationActions`, inside the edit's own step, so
/// "Anulează" takes back the edit and the reminder together.
@MainActor
public enum BillReminders {

    /// What happened to the bill reminder.
    public enum Change: Hashable, Sendable {
        /// Direct debit turned on: the reminder to pay is paused.
        case paused
        /// Direct debit turned off: the reminder for a bill still to pay is back.
        case resumed
    }

    /// Which way the setting moved between two sets of a subscription's values, if it did.
    nonisolated public static func direction(from previous: FieldValues, to values: FieldValues) -> Change? {
        let before = SubscriptionFields.paysByDirectDebit(previous), after = SubscriptionFields.paysByDirectDebit(values)
        guard before != after else { return nil }
        return after ? .paused : .resumed
    }

    /// Pauses or resumes the subscription's bill reminder after its direct debit changed.
    /// Returns what changed, with the receipt that takes back the whole step; nil when
    /// nothing did (the setting didn't move, or there was no reminder to change).
    @discardableResult
    static func follow(_ subscription: Asset, from previous: FieldValues, actions: ObligationActions,
                       today: CalendarDay, calendar: Calendar) throws -> Undoable<Change>? {
        guard let change = direction(from: previous, to: subscription.values) else { return nil }
        let bills = (subscription.obligations ?? []).filter { $0.blueprintKey == SubscriptionFields.billBlueprint }
        var receipt: UndoReceipt?
        switch change {
        case .paused:
            for bill in bills where bill.status == .active { receipt = try actions.pause(bill) }
        case .resumed:
            // Only a bill still to pay; an older one waits for the next bill.
            for bill in bills where bill.status == .paused && bill.dueDay(in: calendar) >= today { receipt = try actions.resume(bill) }
        }
        return receipt.map { Undoable(value: change, receipt: $0) }
    }
}

extension BillReminders.Change {
    /// What the toast after the edit says, with "Anulează" beside it.
    public var toastTitle: LocalizedStringResource {
        switch self {
        case .paused: "Nu-ți mai amintesc să plătești factura: o plătește banca."
        case .resumed: "Îți amintesc din nou să plătești factura."
        }
    }
}
