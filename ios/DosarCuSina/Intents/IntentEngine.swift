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

    /// Whether the surface can ask for Face ID before it closes a deadline of a locked category:
    /// a reminder's „Am rezolvat” opens the app for it, Siri and Shortcuts continue in the app; a
    /// widget runs in the background, so it leaves such a deadline for the app.
    var canAskFaceID: Bool {
        switch self {
        case .notification, .shortcut: true
        case .widget: false
        }
    }
}

/// What a person can do to a deadline without opening the app.
public enum OutsideAction: Hashable, Sendable, Codable {
    case complete
    case snooze(days: Int)

    /// What it does to the deadline, for the lock's one rule (`DeadlineChange`).
    var change: DeadlineChange {
        switch self {
        case .complete: .close
        case .snooze: .snooze
        }
    }
}

/// One action from outside the app, for the cycle the person saw.
public struct OutsideRequest: Hashable, Sendable {
    public var obligationId: UUID
    /// The due day the person saw. The action applies only while the obligation is
    /// still on it; nil (it can't be told) changes nothing.
    public var cycle: CalendarDay?
    public var action: OutsideAction
    public var surface: OutsideSurface
    /// When the person acted, when it was some time before the app could act on it (a widget's
    /// "Gata" left for the app). A deadline counted from when it was done counts from then, not
    /// from when the app next opened. Nil: now.
    public var actedAt: Date?

    public init(obligationId: UUID, cycle: CalendarDay?, action: OutsideAction, surface: OutsideSurface, actedAt: Date? = nil) {
        self.obligationId = obligationId
        self.cycle = cycle
        self.action = action
        self.surface = surface
        self.actedAt = actedAt
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
///
/// A deadline of a category locked on this device follows one rule, the same as Urmează's
/// (`DeadlineChange`): „Amână” goes through as it is, even from the Lock Screen; closing it asks
/// for Face ID or the passcode first (`BiometricVaultManager.confirmClosing`), and a surface that
/// can't ask (`OutsideSurface.canAskFaceID`), or a person who doesn't confirm, changes nothing
/// and leaves it for the app.
@MainActor
enum IntentEngine {
    enum Outcome: Equatable {
        /// Completed; the next due day when it repeats.
        case completed(next: CalendarDay?)
        /// Hidden until that day, when it reminds once.
        case snoozed(until: CalendarDay)
        /// That cycle is already closed, the deadline is paused, an example or gone. Nothing changed.
        case skipped
        /// A deadline of a locked category, and closing it wasn't confirmed with Face ID (or the
        /// surface couldn't ask). Nothing changed; it waits in the app.
        case leftForTheApp
    }

    /// Asks Face ID before a deadline of a locked category is closed from outside the app.
    typealias ClosingConfirmation = @MainActor (_ reason: String) async -> UnlockResult

    /// The vault's one session: Face ID or the passcode, once, if it isn't open already.
    static let vaultConfirmsClosing: ClosingConfirmation = { reason in
        await BiometricVaultManager.shared.confirmClosing(inLockedCategory: true, reason: reason)
    }

    /// Whether this request, as the store is now, asks for Face ID before it is made: closing a
    /// deadline whose category is locked on this device (`DeadlineChange.asksFaceID`), by the
    /// one answer for a section's lock (`Asset.isSensitive(template:)`).
    static func asksFaceID(_ request: OutsideRequest, in context: ModelContext) throws -> Bool {
        let id = request.obligationId
        var descriptor = FetchDescriptor<Obligation>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        // Nothing is asked for a cycle that has gone: the request changes nothing anyway.
        guard let obligation = try context.fetch(descriptor).first, obligation.status == .active,
              let cycle = request.cycle, obligation.dueDay == cycle else { return false }
        return asksFaceID(request.action, for: obligation, in: context)
    }

    private static func asksFaceID(_ action: OutsideAction, for obligation: Obligation, in context: ModelContext) -> Bool {
        // A deadline of the whole household has no section, so no lock.
        guard let asset = obligation.asset else { return false }
        let template = (try? TemplateStore(context: context).template(forKey: asset.templateKey)) ?? nil
        return action.change.asksFaceID(inLockedCategory: asset.isSensitive(template: template))
    }

    /// Applies one request and saves. Throws only when saving fails.
    ///
    /// The cycle is checked against the store as it is now as well as against the context: a
    /// completion from another device lands in the store under the context (`SyncedChanges`), so
    /// an old reminder's "Am rezolvat" never closes the next cycle a second time. Closing a
    /// deadline of a locked category needs `closingConfirmed` (Face ID, asked by `perform`);
    /// without it nothing changes (`.leftForTheApp`).
    @discardableResult
    static func apply(
        _ request: OutsideRequest,
        in context: ModelContext,
        closingConfirmed: Bool = false,
        calendar: Calendar = .dosar,
        now: @escaping () -> Date = { Date() }
    ) throws -> Outcome {
        let id = request.obligationId
        var descriptor = FetchDescriptor<Obligation>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        let actions = ObligationActions(context: context, calendar: calendar, now: now)
        // The one rule for the cycle the person saw (`ObligationActions.isOpen`), the app's own too.
        guard let obligation = try context.fetch(descriptor).first,
              !obligation.isExample,
              let cycle = request.cycle,
              try actions.isOpen(obligation, cycle: cycle)
        else { return .skipped }
        if !closingConfirmed, asksFaceID(request.action, for: obligation, in: context) { return .leftForTheApp }

        switch request.action {
        case .complete:
            // Never later than now: a clock set back on the phone can't date it ahead.
            try actions.complete(obligation, on: request.actedAt.map { min($0, now()) }, cycle: cycle)
            return .completed(next: obligation.status == .active ? obligation.dueDay : nil)
        case .snooze(let days):
            try actions.snooze(obligation, days: days)
            return .snoozed(until: obligation.snoozedUntil ?? cycle)
        }
    }

    /// Applies one request, then re-plans reminders and the widget snapshot through
    /// the app's coordinator, whether it worked or not. A failure is recorded for
    /// Urmează (unless the surface answers in place) and thrown. Closing a deadline of a locked
    /// category asks `confirmClosing` first, where the surface can ask; when it isn't confirmed,
    /// nothing changes, the deadline waits in Urmează (unless the surface answers in place) and
    /// the outcome says so (`.leftForTheApp`).
    @discardableResult
    static func perform(
        _ request: OutsideRequest,
        container: ModelContainer?,
        sideEffects: (ModelContainer) -> SideEffectsCoordinator = { SideEffectsCoordinator.shared(for: $0) },
        failures: OutsideActionFailures = .shared,
        confirmClosing: ClosingConfirmation = vaultConfirmsClosing,
        calendar: Calendar = .dosar,
        now: @escaping () -> Date = { Date() }
    ) async throws -> Outcome {
        guard let container else {
            if !request.surface.answersInPlace { failures.record(request, at: now()) }
            throw IntentError.storeUnavailable
        }
        let outcome: Outcome
        do {
            var confirmed = false
            if request.surface.canAskFaceID, try asksFaceID(request, in: container.mainContext) {
                // The deadline is looked up again after the answer, as it is then.
                let reason = String(localized: "Confirmă că ești tu ca să bifezi termenul protejat.",
                                    comment: "Face ID reason before a deadline of a locked category is closed from a reminder, Siri or Shortcuts.")
                confirmed = await confirmClosing(reason) == .success
            }
            outcome = try apply(request, in: container.mainContext, closingConfirmed: confirmed, calendar: calendar, now: now)
        } catch {
            if !request.surface.answersInPlace { failures.record(request, at: now()) }
            await sideEffects(container).reconcileNow(allowPermissionPrompt: false)
            throw error
        }
        if outcome == .leftForTheApp, !request.surface.answersInPlace { failures.record(request, at: now()) }
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
        calendar: Calendar = .dosar,
        now: @escaping () -> Date = { Date() }
    ) -> Int {
        guard let queue else { return 0 }
        let pending = queue.pending()
        guard !pending.isEmpty else { return 0 }
        var completed = 0
        var handled: [WidgetCompletion] = []
        for item in pending {
            let request = OutsideRequest(obligationId: item.obligationId, cycle: CalendarDay(isoString: item.dueDay), action: .complete, surface: .widget,
                                         actedAt: item.requestedAt)
            do {
                switch try apply(request, in: context, calendar: calendar, now: now) {
                case .completed: completed += 1
                // A locked category's deadline isn't closed without Face ID: it waits in Urmează.
                case .leftForTheApp: failures.record(request, at: item.requestedAt)
                case .snoozed, .skipped: break
                }
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
            surface: .widget,
            actedAt: completion.requestedAt
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
