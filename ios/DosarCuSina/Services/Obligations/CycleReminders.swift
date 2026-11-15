import Foundation

/// How a deadline reminds within one cycle of how it repeats.
///
/// A lead longer than the cycle would fall on or before the day the cycle began (a week's
/// warning on something that repeats every 3 days): it is left out of that cycle, so it never
/// fires in the past, never counts as a warning missed (no catch-up for it) and never makes
/// the deadline look urgent for the whole cycle. The leads the person chose stay stored as
/// they are, so a longer repeat later uses them again. When none of them fits, the deadline
/// reminds on the day itself, so a repeating deadline is never silent.
extension ReminderProfile {
    /// The profile as the cycle that began on `start` and is due on `due` uses it. Nil `start`
    /// (a rule with no set length) keeps every lead.
    public func forCycle(startingOn start: CalendarDay?, due: CalendarDay, calendar: Calendar = .dosar) -> ReminderProfile {
        guard let start else { return self }
        let anchor = urgencyRule.reminderAnchor(for: due, calendar: calendar)
        let fitting = leadDays.filter { $0 == 0 || ReminderLead(days: $0).day(before: anchor, calendar: calendar) > start }
        guard fitting != leadDays else { return self }
        return withLeadDays(fitting.isEmpty ? [0] : fitting)
    }

    /// The profile as the cycle due on `due` uses it, for a deadline that repeats by `rule`.
    public func forCycle(due: CalendarDay, rule: RecurrenceRule, calendar: Calendar = .dosar) -> ReminderProfile {
        forCycle(startingOn: RecurrenceEngine.cycleStart(endingOn: due, rule: rule, calendar: calendar), due: due, calendar: calendar)
    }

    /// Whether `lead` reminds within the cycle due on `due` (the day itself always does).
    public func fits(lead days: Int, due: CalendarDay, rule: RecurrenceRule, calendar: Calendar = .dosar) -> Bool {
        guard days > 0, let start = RecurrenceEngine.cycleStart(endingOn: due, rule: rule, calendar: calendar) else { return true }
        return ReminderLead(days: days).day(before: urgencyRule.reminderAnchor(for: due, calendar: calendar), calendar: calendar) > start
    }
}

extension DosarSchemaV14.Obligation {
    /// Its reminders as this cycle uses them (`ReminderProfile.forCycle`): what reminders,
    /// urgency, Urmează, the widget and the page read. The stored profile (`reminders`) is what
    /// the person edits.
    public var cycleReminders: ReminderProfile {
        reminders.forCycle(due: dueDay, rule: recurrence)
    }

    /// The one urgency rule for this deadline, from the reminders of its cycle.
    public var urgencyRule: UrgencyRule { cycleReminders.urgencyRule }
}
