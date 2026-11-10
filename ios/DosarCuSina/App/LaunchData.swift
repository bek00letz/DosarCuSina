import Foundation
import SwiftData

/// What launch does to the household's data, once per container and in this order: the
/// built-in categories from the app's catalog, the repair list, then the household's own
/// deadlines (the rental income declaration). Each step saves through `UnitOfWork` on its
/// own, as the app's own step (`ChangeOrigin.app`: nothing it changes gets a new change
/// time), so one that fails takes back only its own changes and is tried again at the next
/// launch. Nothing here is the person's to answer, so nothing is shown; a failure goes to the
/// persistence log (`PersistenceLog`), without any of the household's values, and the next
/// step still runs.
@MainActor
enum LaunchData {
    /// The steps, by the name the log gives them.
    enum Step: String, CaseIterable, Sendable {
        case builtInCategories = "Installing the built-in categories"
        case repairList = "Refreshing the repair list"
        case householdDeadlines = "Working out the household's own deadlines"
    }

    /// Runs every step; returns the ones that failed, which the log names.
    @discardableResult
    static func prepare(in context: ModelContext, today: CalendarDay, repairs: DataRepairCenter = .shared) -> [Step] {
        var failed: [Step] = []
        func run(_ step: Step, _ work: () throws -> Void) {
            if !PersistenceLog.attempt(step.rawValue, work) { failed.append(step) }
        }
        run(.builtInCategories) { _ = try TemplateStore(context: context).installBuiltIns() }
        // The repair list: steps that change nothing anyone sees run now; the rest wait for
        // the owner, and the shell's calm prompt says when there is something new.
        run(.repairList) { try repairs.refresh(in: context, announce: true) }
        run(.householdDeadlines) { _ = try reconcileHouseholdRules(in: context, today: today) }
        return failed
    }

    /// The household's own deadlines worked out again from its sections, saved as one step.
    /// Returns whether anything changed.
    @discardableResult
    static func reconcileHouseholdRules(in context: ModelContext, today: CalendarDay) throws -> Bool {
        try UnitOfWork.perform(in: context, origin: .app) {
            try HouseholdRules.reconcile(in: context, today: today)
        }
    }
}
