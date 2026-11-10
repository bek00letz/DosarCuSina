import Foundation

/// What a deadline's due day means for whether something is still valid, decided once.
///
/// Today the due day is the **last valid day**, the way policies and identity documents
/// print it: an RCA "valabilă până la 12.08.2027" still covers 12 August. Whether it should
/// rather be the first day without cover is the owner's call; flipping
/// `dueDayIsLastValidDay` changes every check that asks (`Obligation.isValid(on:)`, the
/// "Ce-ți trebuie" list, the readiness checks), and nothing else needs to.
public enum DueDayValidity {
    /// The due day is the last day something is valid (true), or the first day it isn't (false).
    public static let dueDayIsLastValidDay = true

    /// Whether something due on `due` is still valid on `day`.
    public static func isValid(due: CalendarDay, on day: CalendarDay) -> Bool {
        dueDayIsLastValidDay ? day <= due : day < due
    }

    /// Whether something due on `due` stays valid every day up to and including `day`.
    public static func covers(through day: CalendarDay, due: CalendarDay) -> Bool {
        isValid(due: due, on: day)
    }
}

extension ObligationBlueprint {
    /// Its day comes from a field of the section (a document's expiry), not from itself.
    public var isFieldDriven: Bool {
        if case .field = firstDue { return true }
        return false
    }

    /// The field it takes its day from, when it is field-driven.
    public var drivingField: String? {
        if case .field(let key, _) = firstDue { return key }
        return nil
    }

    /// Whether a deadline from this blueprint is worth making on `day`: a day still ahead,
    /// or one that passed for something that must be renewed by law (an identity card that
    /// expired still needs renewing). A warranty, a minimum period, a bill, a bank card or a
    /// cazier that passed is only history. What the law asks is the profile the section's
    /// values give (`reminders(for:)`: a document's type). Capture's filing plan and a
    /// section's edits both ask this.
    public func isWorthScheduling(on day: CalendarDay, today: CalendarDay, values: FieldValues = FieldValues()) -> Bool {
        day >= today || (kind == .renewal && reminders(for: values).consequence == .legal)
    }
}

extension Obligation {
    /// Whether this deadline is still valid on `day` (an RCA on the day of a trip). See `DueDayValidity`.
    public func isValid(on day: CalendarDay, calendar: Calendar = .dosar) -> Bool {
        DueDayValidity.isValid(due: dueDay, on: day)
    }
}
