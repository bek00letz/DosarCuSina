import Foundation
import SwiftData

/// Obligations that belong to the household rather than to one asset, kept in
/// step with the assets that call for them.
///
/// Today there is one: while at least one tenancy exists, the household files
/// a single "Declarația unică" for rental income every year by 25 May (Codul
/// fiscal, art. 120–122; ANAF). It has no asset: it isn't about one property
/// but about the household's income, so it shows in Urmează but in no section.
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
    ///
    /// Two copies of one (each phone made its own, and "Adaugă" brought them together) become
    /// one: the copy furthest on is kept (`kept(among:)`), and what the others recorded, their
    /// completions and documents, moves onto it before they go. At launch it is the app's own
    /// step (`ChangeOrigin.app`), so nothing it changes gets a new change time; the deadline it
    /// makes has the time it was made.
    @discardableResult
    public static func reconcile(in context: ModelContext, today: CalendarDay, calendar: Calendar = .dosar) throws -> Bool {
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
        if let kept = kept(among: existing) {
            for extra in existing where extra !== kept {
                fold(extra, into: kept)
                context.delete(extra)
                changed = true
            }
            if kept.isExample != isExample { kept.isExample = isExample; changed = true }
            return changed
        }
        let blueprint = rentalDeclaration
        guard let due = RecurrenceEngine.firstDue(for: blueprint, values: FieldValues(), today: today, calendar: calendar) else { return false }
        let obligation = Obligation(title: blueprint.title, kind: blueprint.kind, dueDay: due, recurrence: blueprint.recurrence,
                                    reminders: blueprint.reminders)
        obligation.blueprintKey = blueprint.key
        obligation.notes = blueprint.note
        obligation.isExample = isExample
        context.insert(obligation)
        return true
    }

    /// The copy of a household deadline that stays when there are several, whatever order they
    /// are read in: the one whose cycle is furthest on (a declaration already filed this year
    /// is due next year, so it wins over one still due), then the one with more recorded in
    /// its history, then the one with the smallest id, so every phone keeps the same one.
    static func kept(among copies: [Obligation]) -> Obligation? {
        copies.max { lhs, rhs in
            if lhs.dueDay != rhs.dueDay { return lhs.dueDay < rhs.dueDay }
            let lhsHistory = lhs.historyEntries?.count ?? 0, rhsHistory = rhs.historyEntries?.count ?? 0
            if lhsHistory != rhsHistory { return lhsHistory < rhsHistory }
            // The smaller id is the "larger" here, so `max` keeps it.
            return lhs.id.uuidString > rhs.id.uuidString
        }
    }

    /// Moves what `copy` recorded (its completions and the documents filed with it) onto
    /// `kept`, so nothing of the person's goes with the copy.
    private static func fold(_ copy: Obligation, into kept: Obligation) {
        for entry in copy.historyEntries ?? [] { entry.obligation = kept }
        for attachment in copy.attachments ?? [] { attachment.obligation = kept }
    }
}
