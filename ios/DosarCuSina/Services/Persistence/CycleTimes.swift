import Foundation
import SwiftData

/// Since when a deadline's cycle is known as it now is (`Obligation.cycleKnownAt`): the moment
/// the one reminder that makes up for warnings already passed counts from
/// (`ReminderPlanner.catchUp`). Kept by the unit of work as it saves, beside the change times
/// (`ChangeTimes.stamp`), and written by nothing else but a backup's importer, which leaves a
/// copy it brings to read as its change time (the architecture check's
/// `change-time-outside-change-times`).
///
/// - A deadline a step makes is known from the moment it is made, whoever made it.
/// - A deadline whose due day, reminders' leads, travel margin or status changed is known as it
///   now is from that moment, whoever changed it: the person ("Gata", "Reprogramează", reminders
///   of their own, "Reia") or the app (a repair, reminders that follow a document's type, the
///   household's own deadlines). Its change time is another thing: the app's own steps leave
///   that alone (`ChangeOrigin.app`), so a backup's copy of the person's change is never taken
///   for the older one.
/// - Anything else leaves it, a note, a cost, the reminder time and a snooze among them: the
///   person already knew the cycle, and a snooze has its own reminder on the day it ends.
/// - Undo puts the old moment back with everything else (`ChangeOrigin.restoring` gives none).
enum CycleTimes {
    /// The stored properties of a deadline that make its cycle as the person knows it: the day
    /// it is due, the leads its reminders count back from it (and from a travel cut-off), and
    /// whether it is active, so reminding at all.
    static let cycleProperties: Set<String> = ["dueDayISO", "reminderLeadDays", "travelMarginDays", "statusRaw"]

    /// Gives every deadline the save makes, and every one whose cycle it changes, `now`.
    /// Pending changes are already processed (`ChangeTimes.stamp`).
    static func stamp(_ context: ModelContext, now: Date) {
        for model in context.insertedModelsArray {
            (model as? Obligation)?.cycleKnownAt = now
        }
        let changed = context.changedModelsArray.compactMap { $0 as? Obligation }
        guard !changed.isEmpty else { return }
        // The store still holds every deadline as it was before these changes.
        let store = PersistenceController.context(in: context.container)
        for obligation in changed {
            // Not in the store yet: made by this step, known from the moment it was made.
            guard let stored = Obligation.find(obligation.recordKey, in: store) else { continue }
            if cycle(of: obligation) != cycle(of: stored) { obligation.cycleKnownAt = now }
        }
    }

    /// The values of a deadline's cycle, by property.
    static func cycle(of obligation: Obligation) -> [String: StoredValue] {
        var values: [String: StoredValue] = [:]
        for property in Obligation.storedProperties where cycleProperties.contains(property.name) {
            values[property.name] = property.read(obligation)
        }
        return values
    }
}
