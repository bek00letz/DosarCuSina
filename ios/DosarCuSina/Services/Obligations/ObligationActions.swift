import Foundation
import SwiftData

public enum ObligationActionError: LocalizedError, Equatable {
    /// Only active obligations can be completed or snoozed.
    case notActive
    /// Only the most recent completion can be undone.
    case notLatestCompletion
    /// The blueprint needs a date the person has to enter.
    case missingFirstDueDate(blueprintKey: String)

    public var errorDescription: String? {
        switch self {
        case .notActive:
            return String(localized: "Obligația e pusă pe pauză sau încheiată. Reactiveaz-o mai întâi.")
        case .notLatestCompletion:
            return String(localized: "Poți anula doar ultima bifare.")
        case .missingFirstDueDate:
            return String(localized: "Alege data la care e scadentă prima dată.")
        }
    }
}

/// Every change to an obligation goes through here: the Radar, the asset
/// screen, notification buttons, App Intents and widgets. Each call saves once;
/// side effects (reminders, widgets) follow from the save via `SideEffectsCoordinator`.
@MainActor
public final class ObligationActions {
    public let context: ModelContext
    private let calendar: Calendar
    private let now: () -> Date

    public init(context: ModelContext, calendar: Calendar = .current, now: @escaping () -> Date = { Date() }) {
        self.context = context
        self.calendar = calendar
        self.now = now
    }

    // MARK: Complete and undo

    /// Records that the obligation was done and moves it to its next cycle, or
    /// closes it when it doesn't repeat. The record is a `HistoryEntry` in the
    /// asset's history, the same history repairs and visits go into.
    @discardableResult
    public func complete(
        _ obligation: Obligation,
        on date: Date? = nil,
        cost: Money? = nil,
        metricReading: Double? = nil,
        note: String? = nil,
        items: [LineItemDraft] = [],
        providers: [Provider] = [],
        rating: Int? = nil
    ) throws -> HistoryEntry {
        guard obligation.status == .active else { throw ObligationActionError.notActive }
        let completedAt = date ?? now()
        let completedDay = CalendarDay(completedAt, calendar: calendar)

        let entry = HistoryEntry(kind: .forCompleting(obligation.kind), title: obligation.title, occurredAt: completedAt)
        entry.cycleDueDate = obligation.dueDate
        entry.previousStatusRaw = obligation.statusRaw
        entry.previousDueMetric = obligation.dueMetric
        entry.totalCost = cost
        entry.metricReading = metricReading
        entry.note = note
        entry.rating = rating.map { min(max($0, 1), 5) }
        entry.isExample = obligation.isExample
        context.insert(entry)
        entry.obligation = obligation
        entry.asset = obligation.asset
        entry.providers = providers
        HouseholdMutations.addItems(items, to: entry, in: context)

        if let metricReading, let asset = obligation.asset {
            HouseholdMutations.recordReading(metricReading, on: asset, at: completedAt, unit: obligation.metricUnit, in: context)
        }

        let recurrenceContext = HouseholdMutations.recurrenceContext(for: obligation, currentMetric: metricReading)
        if let next = RecurrenceEngine.nextDue(
            after: obligation.dueDay(in: calendar),
            completedOn: completedDay,
            rule: obligation.recurrence,
            context: recurrenceContext,
            calendar: calendar
        ) {
            obligation.setDueDay(next.day, calendar: calendar)
            obligation.dueMetric = next.metric
            entry.nextDueDate = obligation.dueDate
        } else {
            obligation.status = .done
        }
        obligation.snoozedUntil = nil
        obligation.updatedAt = now()
        try save()
        return entry
    }

    /// Puts the obligation back the way it was before `entry` completed it and
    /// removes the entry. Only the latest completion can be undone.
    public func undo(_ entry: HistoryEntry) throws {
        guard let obligation = entry.obligation, let cycleDueDate = entry.cycleDueDate else {
            context.delete(entry)
            try save()
            return
        }
        guard obligation.history.first?.id == entry.id else { throw ObligationActionError.notLatestCompletion }
        obligation.dueDate = cycleDueDate
        obligation.dueMetric = entry.previousDueMetric
        obligation.status = entry.previousStatusRaw.flatMap(ObligationStatus.init(rawValue:)) ?? .active
        obligation.updatedAt = now()
        context.delete(entry)
        try save()
    }

    public func undoLastCompletion(of obligation: Obligation) throws {
        guard let latest = obligation.history.first else { return }
        try undo(latest)
    }

    // MARK: Schedule

    /// Hides the obligation and its reminders for `days` days, then reminds once.
    public func snooze(_ obligation: Obligation, days: Int) throws {
        guard obligation.status == .active else { throw ObligationActionError.notActive }
        let today = CalendarDay(now(), calendar: calendar)
        obligation.snoozedUntil = today.adding(days: max(1, days), calendar: calendar).startDate(in: calendar)
        obligation.updatedAt = now()
        try save()
    }

    public func clearSnooze(_ obligation: Obligation) throws {
        obligation.snoozedUntil = nil
        obligation.updatedAt = now()
        try save()
    }

    /// Changes how the obligation reminds (lead days, grace, follow-up after lapsing).
    public func setReminders(_ obligation: Obligation, _ profile: ReminderProfile) throws {
        obligation.reminders = profile
        obligation.updatedAt = now()
        try save()
    }

    /// The "follow up after it lapses" checkbox.
    public func setFollowUpAfterLapse(_ obligation: Obligation, _ isOn: Bool) throws {
        obligation.followUpAfterLapse = isOn
        obligation.updatedAt = now()
        try save()
    }

    public func reschedule(_ obligation: Obligation, to day: CalendarDay) throws {
        obligation.setDueDay(day, calendar: calendar)
        obligation.snoozedUntil = nil
        obligation.updatedAt = now()
        try save()
    }

    public func pause(_ obligation: Obligation) throws {
        try setStatus(.paused, of: obligation)
    }

    public func resume(_ obligation: Obligation) throws {
        try setStatus(.active, of: obligation)
    }

    public func archive(_ obligation: Obligation) throws {
        try setStatus(.archived, of: obligation)
    }

    public func delete(_ obligation: Obligation) throws {
        context.delete(obligation)
        try save()
    }

    // MARK: Create

    @discardableResult
    public func create(
        title: String,
        kind: ObligationKind,
        dueDay: CalendarDay,
        for asset: Asset?,
        recurrence: RecurrenceRule = .none,
        reminders: ReminderProfile? = nil,
        estimatedCost: Money? = nil,
        provider: String? = nil,
        reference: String? = nil,
        notes: String? = nil
    ) throws -> Obligation {
        let obligation = Obligation(
            title: title,
            kind: kind,
            dueDay: dueDay,
            recurrence: recurrence,
            reminders: reminders,
            estimatedCost: estimatedCost,
            calendar: calendar
        )
        obligation.provider = provider
        obligation.reference = reference
        obligation.notes = notes
        context.insert(obligation)
        obligation.asset = asset
        obligation.isExample = asset?.isExample ?? false
        try save()
        return obligation
    }

    /// Creates an obligation from a template blueprint. `firstDue` overrides the
    /// blueprint's own rule; it is required when the blueprint asks for a date.
    @discardableResult
    public func create(from blueprint: ObligationBlueprint, for asset: Asset, firstDue: CalendarDay? = nil) throws -> Obligation {
        let obligation = try HouseholdMutations.makeObligation(from: blueprint, for: asset, firstDue: firstDue, today: CalendarDay(now(), calendar: calendar), calendar: calendar, in: context)
        try save()
        return obligation
    }

    // MARK: Private

    private func setStatus(_ status: ObligationStatus, of obligation: Obligation) throws {
        obligation.status = status
        if status != .active { obligation.snoozedUntil = nil }
        obligation.updatedAt = now()
        try save()
    }

    private func save() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

extension DosarSchemaV2.Obligation {
    /// The counter unit for metric-based obligations, such as `km`.
    public var metricUnit: String? {
        if case .metric(_, let unit, _) = recurrence { return unit }
        return nil
    }
}
