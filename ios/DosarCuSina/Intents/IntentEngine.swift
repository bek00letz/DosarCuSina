import Foundation
import SwiftData

/// What App Intents and widgets do to the household, on the same engine as
/// the app: `ObligationActions` for the change, `SideEffectsCoordinator` for
/// reminders, badge and widgets afterwards. An intent may run while no window
/// is open (so the app's own coordinator isn't running); `refreshSideEffects`
/// runs one pass so a widget tap is reflected at once.
@MainActor
enum IntentEngine {
    enum Outcome: Equatable {
        /// Completed; the next due day when it repeats.
        case completed(next: CalendarDay?)
        /// Already done for that cycle, paused, or gone. Nothing changed.
        case skipped
    }

    /// Completes an obligation. With `cycle`, only if it is still on that cycle,
    /// so a request made for one cycle never closes the next.
    @discardableResult
    static func complete(obligationID: UUID, cycle: CalendarDay? = nil, in context: ModelContext, calendar: Calendar = .current) throws -> Outcome {
        var descriptor = FetchDescriptor<Obligation>(predicate: #Predicate { $0.id == obligationID })
        descriptor.fetchLimit = 1
        guard let obligation = try context.fetch(descriptor).first, obligation.status == .active else { return .skipped }
        if let cycle, obligation.dueDay(in: calendar) != cycle { return .skipped }
        try ObligationActions(context: context, calendar: calendar).complete(obligation)
        return .completed(next: obligation.status == .active ? obligation.dueDay(in: calendar) : nil)
    }

    /// Applies widget taps the widget extension left in the App Group.
    /// Returns how many obligations were completed.
    @discardableResult
    static func applyQueuedWidgetCompletions(queue: WidgetCompletionQueue? = .shared(), in context: ModelContext, calendar: Calendar = .current) -> Int {
        guard let queue else { return 0 }
        let pending = queue.pending()
        guard !pending.isEmpty else { return 0 }
        var completed = 0
        for request in pending {
            guard let cycle = CalendarDay(isoString: request.dueDay) else { continue }
            if case .completed = (try? complete(obligationID: request.obligationId, cycle: cycle, in: context, calendar: calendar)) ?? .skipped {
                completed += 1
            }
        }
        queue.remove(pending)
        return completed
    }

    /// One reconcile pass: reminders, badge and the widget snapshot follow the save.
    static func refreshSideEffects(container: ModelContainer) async {
        await SideEffectsCoordinator(container: container).reconcileNow(allowPermissionPrompt: false)
    }
}

/// The app's side of `CompleteFromWidgetIntent`: complete through the engine now.
enum WidgetCompletionHandler {
    static func handle(_ completion: WidgetCompletion) async {
        await MainActor.run {
            guard let container = PersistenceController.shared.container,
                  let cycle = CalendarDay(isoString: completion.dueDay) else { return }
            _ = try? IntentEngine.complete(obligationID: completion.obligationId, cycle: cycle, in: container.mainContext)
        }
        if let container = await MainActor.run(body: { PersistenceController.shared.container }) {
            await IntentEngine.refreshSideEffects(container: container)
        }
    }
}
