import Foundation
import SwiftData

/// Where an action from outside the app came from.
public enum OutsideSurface: String, Codable, CaseIterable, Sendable {
    /// "Am rezolvat" or "Amână 3 zile" on a reminder.
    case notification
    /// "Gata" on a Home Screen or Lock Screen widget.
    case widget
    /// Siri or a shortcut.
    case shortcut

    /// Siri and Shortcuts show a failure right away; a reminder or a widget can't,
    /// so their failures wait in Urmează for the next time the app opens.
    var answersInPlace: Bool { self == .shortcut }
}

/// What a person can do to a deadline without opening the app.
public enum OutsideAction: Hashable, Sendable, Codable {
    case complete
    case snooze(days: Int)
}

/// One action from outside the app, for the cycle the person saw.
public struct OutsideRequest: Hashable, Sendable {
    public var obligationId: UUID
    /// The due day the person saw. The action applies only while the obligation is
    /// still on it; nil (it can't be told) changes nothing.
    public var cycle: CalendarDay?
    public var action: OutsideAction
    public var surface: OutsideSurface

    public init(obligationId: UUID, cycle: CalendarDay?, action: OutsideAction, surface: OutsideSurface) {
        self.obligationId = obligationId
        self.cycle = cycle
        self.action = action
        self.surface = surface
    }
}

/// The one way in for every "done" and "amână" from outside the app: reminder
/// buttons, widgets, Siri and Shortcuts. It changes the household through
/// `ObligationActions`, the same engine as the app's own buttons, only for the
/// cycle the person saw, so an old reminder or a late widget tap never closes the
/// next cycle. Every action ends with a pass of `SideEffectsCoordinator`, which
/// re-plans reminders, clears reminders already shown for a closed cycle and
/// rewrites the widget snapshot. A failure is never dropped: Siri says it, and a
/// reminder or widget tap that couldn't be saved is shown in Urmează.
@MainActor
enum IntentEngine {
    enum Outcome: Equatable {
        /// Completed; the next due day when it repeats.
        case completed(next: CalendarDay?)
        /// Hidden until that day, when it reminds once.
        case snoozed(until: CalendarDay)
        /// That cycle is already closed, the deadline is paused, an example or gone. Nothing changed.
        case skipped
    }

    /// Applies one request and saves. Throws only when saving fails.
    ///
    /// The cycle is checked against the store as it is now as well as against the context: a
    /// completion from another device lands in the store under the context (`SyncedChanges`), so
    /// an old reminder's "Am rezolvat" never closes the next cycle a second time.
    @discardableResult
    static func apply(
        _ request: OutsideRequest,
        in context: ModelContext,
        calendar: Calendar = .dosar,
        now: @escaping () -> Date = { Date() }
    ) throws -> Outcome {
        let id = request.obligationId
        var descriptor = FetchDescriptor<Obligation>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        func stillOpen(_ obligation: Obligation?) -> Bool {
            guard let obligation, obligation.status == .active, !obligation.isExample, let cycle = request.cycle else { return false }
            return obligation.dueDay == cycle
        }
        let store = PersistenceController.context(in: context.container)
        guard let obligation = try context.fetch(descriptor).first,
              stillOpen(obligation),
              stillOpen(try store.fetch(descriptor).first),
              let cycle = request.cycle
        else { return .skipped }

        let actions = ObligationActions(context: context, calendar: calendar, now: now)
        switch request.action {
        case .complete:
            try actions.complete(obligation)
            return .completed(next: obligation.status == .active ? obligation.dueDay : nil)
        case .snooze(let days):
            try actions.snooze(obligation, days: days)
            return .snoozed(until: obligation.snoozedUntil ?? cycle)
        }
    }

    /// Applies one request, then re-plans reminders and the widget snapshot through
    /// the app's coordinator, whether it worked or not. A failure is recorded for
    /// Urmează (unless the surface answers in place) and thrown.
    @discardableResult
    static func perform(
        _ request: OutsideRequest,
        container: ModelContainer?,
        sideEffects: (ModelContainer) -> SideEffectsCoordinator = { SideEffectsCoordinator.shared(for: $0) },
        failures: OutsideActionFailures = .shared,
        calendar: Calendar = .dosar,
        now: @escaping () -> Date = { Date() }
    ) async throws -> Outcome {
        guard let container else {
            if !request.surface.answersInPlace { failures.record(request, at: now()) }
            throw IntentError.storeUnavailable
        }
        let outcome: Outcome
        do {
            outcome = try apply(request, in: container.mainContext, calendar: calendar, now: now)
        } catch {
            if !request.surface.answersInPlace { failures.record(request, at: now()) }
            await sideEffects(container).reconcileNow(allowPermissionPrompt: false)
            throw error
        }
        await sideEffects(container).reconcileNow(allowPermissionPrompt: false)
        return outcome
    }

    /// Applies widget taps the widget extension left in the App Group (iOS 26,
    /// where the extension can't reach the database). Only taps that were applied,
    /// or whose cycle has gone, leave the queue; one that couldn't be saved stays
    /// to be tried again and is shown in Urmează meanwhile.
    /// Returns how many obligations were completed.
    @discardableResult
    static func applyQueuedWidgetCompletions(
        queue: WidgetCompletionQueue? = .shared(),
        in context: ModelContext,
        failures: OutsideActionFailures = .shared,
        calendar: Calendar = .dosar
    ) -> Int {
        guard let queue else { return 0 }
        let pending = queue.pending()
        guard !pending.isEmpty else { return 0 }
        var completed = 0
        var handled: [WidgetCompletion] = []
        for item in pending {
            let request = OutsideRequest(obligationId: item.obligationId, cycle: CalendarDay(isoString: item.dueDay), action: .complete, surface: .widget)
            do {
                if case .completed = try apply(request, in: context, calendar: calendar) { completed += 1 }
                handled.append(item)
            } catch {
                failures.record(request, at: item.requestedAt)
            }
        }
        queue.remove(handled)
        // Saves already reach the coordinator; a tap that changed nothing still
        // has to bring the item back on the widget, which hid it at once.
        SideEffectsCoordinator.running?.setNeedsReconcile(allowPermissionPrompt: false)
        return completed
    }
}

/// The app's side of `CompleteFromWidgetIntent`: complete through the engine now.
enum WidgetCompletionHandler {
    @MainActor
    static func handle(_ completion: WidgetCompletion) async {
        let request = OutsideRequest(
            obligationId: completion.obligationId,
            cycle: CalendarDay(isoString: completion.dueDay),
            action: .complete,
            surface: .widget
        )
        do {
            try await IntentEngine.perform(request, container: PersistenceController.shared.container)
        } catch {
            // Recorded by the engine; Urmează shows it the next time the app opens.
        }
    }
}

/// Reminder buttons and widget taps that couldn't be saved, kept on this phone
/// until the cycle they were for closes or the person dismisses them. Urmează
/// shows them calmly at the top.
public struct OutsideActionFailures: Sendable {
    public struct Failure: Codable, Hashable, Sendable, Identifiable {
        public var obligationId: UUID
        /// `yyyy-MM-dd` of the cycle the tap was for.
        public var cycle: String?
        public var action: OutsideAction
        public var surface: OutsideSurface
        public var failedAt: Date

        public var id: UUID { obligationId }
    }

    /// Posted when a failure is recorded or dismissed.
    public static let didChange = Notification.Name("OutsideActionFailures.didChange")
    static let key = "outsideActions.failures"

    public static let shared = OutsideActionFailures(suiteName: nil)

    private let suiteName: String?

    /// - Parameter suiteName: nil for the app's own defaults; tests pass their own.
    public init(suiteName: String?) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func all() -> [Failure] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        do {
            return try MachineText.jsonDecoder().decode([Failure].self, from: data)
        } catch {
            // Written by this app only; something unreadable is dropped rather than shown wrong.
            defaults.removeObject(forKey: Self.key)
            return []
        }
    }

    /// Keeps one failure per obligation, the latest.
    func record(_ request: OutsideRequest, at date: Date) {
        var items = all().filter { $0.obligationId != request.obligationId }
        items.append(Failure(obligationId: request.obligationId, cycle: request.cycle?.isoString, action: request.action, surface: request.surface, failedAt: date))
        write(items)
    }

    public func dismiss(_ obligationId: UUID) {
        let items = all()
        guard items.contains(where: { $0.obligationId == obligationId }) else { return }
        write(items.filter { $0.obligationId != obligationId })
    }

    /// Failures still worth showing, with what they are about: the deadline is
    /// still open on the cycle that was tapped. The rest are forgotten.
    public func current(in snapshots: [ObligationSnapshot]) -> [(failure: Failure, obligation: ObligationSnapshot)] {
        let byId = Dictionary(snapshots.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let items = all()
        let open = items.compactMap { failure -> (Failure, ObligationSnapshot)? in
            guard let obligation = byId[failure.obligationId], obligation.status == .active,
                  failure.cycle == obligation.dueDay.isoString else { return nil }
            return (failure, obligation)
        }
        if open.count != items.count { write(open.map(\.0)) }
        return open.sorted { $0.0.failedAt > $1.0.failedAt }
    }

    private func write(_ items: [Failure]) {
        if items.isEmpty {
            defaults.removeObject(forKey: Self.key)
        } else {
            do {
                defaults.set(try MachineText.jsonEncoder().encode(items), forKey: Self.key)
            } catch {
                return
            }
        }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}
