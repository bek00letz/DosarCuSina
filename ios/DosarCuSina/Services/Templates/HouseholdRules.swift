import Foundation
import SwiftData

/// Obligations that belong to the household rather than to one asset, kept in
/// step with the assets that call for them.
///
/// Today there is one: while at least one tenancy exists, the household files
/// a single "Declarația unică" for rental income every year by 25 May (Codul
/// fiscal, art. 120–122; ANAF). It has no asset: it isn't about one property
/// but about the household's income, so it shows in Urmează but in no section.
@MainActor
public enum HouseholdRules {
    public static let rentalDeclarationKey = "household.rentalDeclaration"

    public static var rentalDeclaration: ObligationBlueprint {
        ObligationBlueprint(
            key: rentalDeclarationKey,
            title: String(localized: "Declarația unică pentru chirii"),
            kind: .tax,
            recurrence: .fixedDates([MonthDay(month: 5, day: 25)]),
            firstDue: .nextFixedDate,
            reminders: ReminderProfile(leadDays: [30, 7], consequence: .legal, graceDays: 0, followUpAfterLapse: true),
            note: String(localized: "Venitul din chirii se declară la ANAF până pe 25 mai.")
        )
    }

    /// Creates or removes household obligations to match the assets. Doesn't save;
    /// callers fold it into their own single save. Returns whether anything changed.
    @discardableResult
    public static func reconcile(in context: ModelContext, today: CalendarDay, calendar: Calendar = .current) throws -> Bool {
        let tenancyKey = BuiltInTemplates.Key.tenancy
        let tenancies = try context.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.templateKey == tenancyKey }))
            .filter { !$0.isDeleted }
        let key = rentalDeclarationKey
        let existing = try context.fetch(FetchDescriptor<Obligation>(predicate: #Predicate { $0.blueprintKey == key }))
            .filter { !$0.isDeleted }

        guard !tenancies.isEmpty else {
            existing.forEach(context.delete)
            return !existing.isEmpty
        }
        // Examples only produce an example declaration; one real tenancy makes it real.
        let isExample = tenancies.allSatisfy(\.isExample)
        var changed = false
        if let first = existing.first {
            for extra in existing.dropFirst() { context.delete(extra); changed = true }
            if first.isExample != isExample { first.isExample = isExample; changed = true }
            return changed
        }
        let blueprint = rentalDeclaration
        guard let due = RecurrenceEngine.firstDue(for: blueprint, values: FieldValues(), today: today, calendar: calendar) else { return false }
        let obligation = Obligation(title: blueprint.title, kind: blueprint.kind, dueDay: due, recurrence: blueprint.recurrence,
                                    reminders: blueprint.reminders, calendar: calendar)
        obligation.blueprintKey = blueprint.key
        obligation.notes = blueprint.note
        obligation.isExample = isExample
        context.insert(obligation)
        return true
    }
}
