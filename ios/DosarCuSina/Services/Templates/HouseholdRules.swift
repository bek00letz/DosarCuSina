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
            completion: .rentalDeclaration,
            recurrence: .fixedDates([MonthDay(month: 5, day: 25)]),
            firstDue: .nextFixedDate,
            reminders: ReminderProfile(leadDays: [30, 7], consequence: .legal, graceDays: 0, followUpAfterLapse: true),
            note: String(localized: "Venitul din chirii se declară la ANAF până pe 25 mai.")
        )
    }

    /// Every household deadline's blueprint: what a deadline with no section was made from.
    public static var blueprints: [ObligationBlueprint] { [rentalDeclaration] }

    /// Creates or removes household obligations to match the assets. Doesn't save;
    /// callers fold it into their own single save. Returns whether anything changed.
    ///
    /// With no tenancy, a declaration goes only once the binder has all arrived (`CloudArrival`)
    /// and only when nothing of the person's is on it (a completion, a document): one they
    /// filed or attached a paper to stays, as theirs.
    ///
    /// Two copies of one (each phone made its own, and "Adaugă" brought them together) become
    /// one: the copy with the person's history on it is kept (`kept(among:)`), and what the
    /// others recorded, their completions and documents, moves onto it before they go, with
    /// their notes and reminders where the kept copy has none of its own. A new declaration is
    /// made only once the binder has all arrived (`CloudArrival`): the person's own may still be
    /// on its way from iCloud. At launch it is the app's own step (`ChangeOrigin.app`), so nothing
    /// it changes gets a new change time; the deadline it makes has the time it was made.
    @discardableResult
    public static func reconcile(in context: ModelContext, today: CalendarDay, calendar: Calendar = .dosar) throws -> Bool {
        let tenancyKey = BuiltInTemplates.Key.tenancy
        let tenancies = try context.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.templateKey == tenancyKey }))
            .filter { !$0.isDeleted }
        let key = rentalDeclarationKey
        let existing = try context.fetch(FetchDescriptor<Obligation>(predicate: #Predicate { $0.blueprintKey == key }))
            .filter { !$0.isDeleted }

        guard !tenancies.isEmpty else {
            // A binder still arriving from iCloud may bring its tenancy later: nothing goes before
            // it has arrived (`CloudArrival`), or the removal would reach every device.
            guard CloudArrival.of(context.container).isWhole else { return false }
            // A declaration with something of the person's on it (a completion, a document) is
            // their record and stays; the income it declares is still due after the last tenancy
            // ends. Only one nobody has used goes.
            let unused = existing.filter { ($0.historyEntries ?? []).isEmpty && ($0.attachments ?? []).isEmpty }
            unused.forEach(context.delete)
            return !unused.isEmpty
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
        // The person's declaration may still be on its way: one made now would be a second copy.
        guard CloudArrival.of(context.container).isWhole else { return false }
        let blueprint = rentalDeclaration
        guard let due = RecurrenceEngine.firstDue(for: blueprint, values: FieldValues(), today: today, calendar: calendar) else { return false }
        let obligation = Obligation(title: blueprint.title, kind: blueprint.kind, dueDay: due, recurrence: blueprint.recurrence,
                                    reminders: blueprint.reminders)
        obligation.blueprintKey = blueprint.key
        obligation.notes = blueprint.deadlineNote
        obligation.isExample = isExample
        context.insert(obligation)
        return true
    }

    /// The copy of a household deadline that stays when there are several, whatever order they
    /// are read in, so every phone keeps the same one:
    /// 1. a copy with a completion: the person filed it. The one furthest on stays (a declaration
    ///    filed this year is due next year), so no reminder comes back for a cycle already filed;
    /// 2. else a copy with something else of the person's on it (a document, their own note, a
    ///    snooze, reminders they changed): the overdue copy they were working on, never a fresh
    ///    copy the app just made;
    /// 3. else the earliest still open: the one that reminds soonest;
    /// 4. then the smallest id.
    static func kept(among copies: [Obligation]) -> Obligation? {
        copies.min(by: staysBefore)
    }

    /// Whether `lhs` stays rather than `rhs` (`kept(among:)`'s order).
    private static func staysBefore(_ lhs: Obligation, _ rhs: Obligation) -> Bool {
        let lhsFiled = !(lhs.historyEntries ?? []).isEmpty, rhsFiled = !(rhs.historyEntries ?? []).isEmpty
        if lhsFiled != rhsFiled { return lhsFiled }
        if lhsFiled, lhs.dueDay != rhs.dueDay { return lhs.dueDay > rhs.dueDay }
        let lhsMarked = hasPersonsMarks(lhs), rhsMarked = hasPersonsMarks(rhs)
        if lhsMarked != rhsMarked { return lhsMarked }
        let lhsOpen = lhs.status == .active, rhsOpen = rhs.status == .active
        if lhsOpen != rhsOpen { return lhsOpen }
        if lhs.dueDay != rhs.dueDay { return lhs.dueDay < rhs.dueDay }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Whether the person left something of theirs on a copy besides a completion: a document,
    /// a note other than the one the app writes, a snooze, reminders or a reminder time they chose.
    static func hasPersonsMarks(_ copy: Obligation) -> Bool {
        !(copy.attachments ?? []).isEmpty || hasOwnNote(copy) || copy.snoozedUntil != nil
            || copy.remindersCustomized || copy.reminderMinuteOfDay != nil
    }

    /// A note the person wrote: anything but none or the blueprint's own.
    private static func hasOwnNote(_ copy: Obligation) -> Bool {
        guard let note = copy.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty else { return false }
        return note != rentalDeclaration.deadlineNote?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Moves what `copy` recorded (its completions and the documents filed with it) onto
    /// `kept`, so nothing of the person's goes with the copy; its note and the reminders the
    /// person chose come too where `kept` has none of its own, and its snooze when both are
    /// for the same day.
    private static func fold(_ copy: Obligation, into kept: Obligation) {
        for entry in copy.historyEntries ?? [] { entry.obligation = kept }
        for attachment in copy.attachments ?? [] { attachment.obligation = kept }
        if hasOwnNote(copy), !hasOwnNote(kept) { kept.notes = copy.notes }
        if copy.remindersCustomized, !kept.remindersCustomized {
            kept.keptReminders = copy.keptReminders
            kept.remindersCustomized = true
        }
        if kept.reminderMinuteOfDay == nil, let minute = copy.reminderMinuteOfDay { kept.reminderMinuteOfDay = minute }
        if kept.snoozedUntil == nil, kept.dueDay == copy.dueDay, let snooze = copy.snoozedUntil { kept.snoozedUntil = snooze }
    }
}
