import Foundation

/// The urgency rule behind a date a screen shows, so every badge, hero line and
/// form says what Urmează says. A date is as urgent as the deadline it drives:
/// the reminders of that deadline decide (`ReminderProfile.urgencyRule`). A date
/// no deadline reminds about is urgent only on the day and once it has passed.
enum DateUrgency {
    /// A date shown on an asset (an expiry, a warranty's or a contract's end): the
    /// rule of the asset's open deadline due that day, with the reminders the person set.
    static func rule(for day: CalendarDay, on asset: Asset?, calendar: Calendar = .dosar) -> UrgencyRule {
        asset?.activeObligations.first { $0.dueDay(in: calendar) == day }?.reminders.urgencyRule ?? .noReminders
    }

    /// A date field being filled in: the rule of the deadline the field starts (the
    /// template's deadline anchored on it), as the asset has it when it exists, else as
    /// the template would make it for these values.
    static func rule(forField key: String, values: FieldValues, definition: TemplateDefinition?, asset: Asset? = nil) -> UrgencyRule {
        guard let blueprint = definition?.blueprints.first(where: { $0.startsFrom(field: key) }) else { return .noReminders }
        if let live = asset?.activeObligations.first(where: { $0.blueprintKey == blueprint.key }) {
            return live.reminders.urgencyRule
        }
        return blueprint.reminders(for: values).urgencyRule
    }
}

extension ObligationBlueprint {
    /// Whether its first due day is read from `field`.
    func startsFrom(field key: String) -> Bool {
        if case .field(let anchor, _) = firstDue { return anchor == key }
        return false
    }
}

extension Obligation {
    /// Its urgency today, by the one rule. Every screen showing one obligation asks this.
    func urgency(now: Date = Date(), calendar: Calendar = .dosar) -> AttentionUrgency {
        reminders.urgencyRule.urgency(of: dueDay(in: calendar), today: CalendarDay(now, calendar: calendar), calendar: calendar)
    }
}
