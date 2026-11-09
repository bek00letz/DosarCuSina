import Foundation
import SwiftData

/// What launch does to the household's data, once per container and in this order: the
/// built-in categories from the app's catalog, the repair list, then the household's own
/// deadlines (the rental income declaration). Each step saves through `UnitOfWork` on its
/// own, so one that fails takes back only its own changes and is tried again at the next
/// launch; nothing here is the person's to answer, so nothing is shown.
@MainActor
enum LaunchData {
    static func prepare(in context: ModelContext, today: CalendarDay, repairs: DataRepairCenter = .shared) {
        _ = try? TemplateStore(context: context).installBuiltIns()
        // The repair list: steps that change nothing anyone sees run now; the rest wait for
        // the owner, and the shell's calm prompt says when there is something new.
        try? repairs.refresh(in: context, announce: true)
        _ = try? reconcileHouseholdRules(in: context, today: today)
    }

    /// The household's own deadlines worked out again from its sections, saved as one step.
    /// Returns whether anything changed.
    @discardableResult
    static func reconcileHouseholdRules(in context: ModelContext, today: CalendarDay) throws -> Bool {
        try UnitOfWork.perform(in: context) {
            try HouseholdRules.reconcile(in: context, today: today)
        }
    }
}
