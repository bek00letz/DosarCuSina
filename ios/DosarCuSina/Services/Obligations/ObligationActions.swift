import Foundation
import SwiftData

public enum ObligationActionError: LocalizedError, Equatable {
    /// Only active obligations can be completed or snoozed.
    case notActive
    /// The blueprint needs a date the person has to enter.
    case missingFirstDueDate(blueprintKey: String)

    public var errorDescription: String? {
        switch self {
        case .notActive:
            return String(localized: "Obligația e pusă pe pauză sau încheiată. Reactiveaz-o mai întâi.")
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

    public init(context: ModelContext, calendar: Calendar = .dosar, now: @escaping () -> Date = { Date() }) {
        self.context = context
        self.calendar = calendar
        self.now = now
    }

    // MARK: Complete

    /// Records that the obligation was done and moves it to its next cycle, or
    /// closes it when it doesn't repeat. The record is a `HistoryEntry` in the
    /// asset's history, the same history repairs and visits go into. The receipt
    /// takes it all back ("Anulează"), the reading it recorded included; deleting an
    /// older completion from Istoric is `HistoryActions.delete`.
    @discardableResult
    public func complete(
        _ obligation: Obligation,
        on date: Date? = nil,
        cost: Money? = nil,
        metricReading: Double? = nil,
        note: String? = nil,
        items: [LineItemDraft] = [],
        providers: [Provider] = [],
        rating: Int? = nil,
        lowerReading: LowerReadingAnswer? = nil
    ) throws -> Undoable<HistoryEntry> {
        guard obligation.status == .active else { throw ObligationActionError.notActive }
        let completedAt = date ?? now()
        // Every question first, before anything is written (`StepQuestion`).
        let reading = plannedReading(metricReading, completing: obligation, on: completedAt)
        try HouseholdMutations.askAboutReading(reading, answer: lowerReading)
        return try UnitOfWork.performUndoable(in: context, now: now()) {
            let completedDay = CalendarDay(completedAt, calendar: calendar)

            let entry = HistoryEntry(kind: .forCompleting(obligation.kind), title: obligation.title, occurredAt: completedAt)
            entry.cycleDueDay = obligation.dueDay
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

            if let reading {
                try HouseholdMutations.recordReading(reading, answer: lowerReading, isExample: obligation.isExample, in: context)
            }

            let recurrenceContext = HouseholdMutations.recurrenceContext(for: obligation, currentMetric: metricReading, calendar: calendar)
            if let next = RecurrenceEngine.nextDue(
                after: obligation.dueDay,
                completedOn: completedDay,
                rule: obligation.recurrence,
                context: recurrenceContext,
                calendar: calendar
            ) {
                obligation.dueDay = next.day
                obligation.dueMetric = next.metric
                entry.nextDueDay = obligation.dueDay
            } else {
                obligation.status = .done
            }
            obligation.snoozedUntil = nil
            try save()
            return entry
        }
    }

    /// The reading "Gata" records with the counter the person read (`metricReading`): on the
    /// deadline's section, in the deadline's unit, on the day it was done. Asked about before
    /// the step's unit opens, by `complete` and by any flow that completes inside a larger step.
    func plannedReading(_ metricReading: Double?, completing obligation: Obligation, on date: Date) -> PlannedReading? {
        guard let metricReading, let asset = obligation.asset else { return nil }
        return PlannedReading(metricReading, on: asset, at: date, source: .person, unit: obligation.metricUnit)
    }

    /// A completion from before the binder knew the obligation (last year's ITP): logged
    /// in the history with the cycle it closed, without moving the obligation. Only the
    /// example loader uses it today, so its entry is an example exactly when the
    /// obligation is one.
    @discardableResult
    func recordPastCompletion(of obligation: Obligation, on date: Date, cost: Money?) throws -> HistoryEntry {
        let entry = HistoryEntry(kind: .forCompleting(obligation.kind), title: obligation.title, occurredAt: date)
        entry.cycleDueDay = CalendarDay(date, calendar: calendar)
        entry.nextDueDay = obligation.dueDay
        entry.previousStatusRaw = ObligationStatus.active.rawValue
        entry.totalCost = cost
        entry.isExample = obligation.isExample
        context.insert(entry)
        entry.obligation = obligation
        entry.asset = obligation.asset
        try save()
        return entry
    }

    // MARK: Schedule

    /// Hides the obligation and its reminders for `days` days, then reminds once.
    @discardableResult
    public func snooze(_ obligation: Obligation, days: Int) throws -> UndoReceipt {
        try UnitOfWork.performUndoable(in: context, now: now()) {
            guard obligation.status == .active else { throw ObligationActionError.notActive }
            let today = CalendarDay(now(), calendar: calendar)
            obligation.snoozedUntil = today.adding(days: max(1, days), calendar: calendar)
            try save()
        }.receipt
    }

    /// Brings a snoozed obligation back now ("Anulează amânarea"). Undoable.
    @discardableResult
    public func clearSnooze(_ obligation: Obligation) throws -> UndoReceipt {
        try UnitOfWork.performUndoable(in: context, now: now()) {
            obligation.snoozedUntil = nil
            try save()
        }.receipt
    }

    /// Changes how the obligation reminds (lead days, grace, follow-up after lapsing), as the
    /// person chose: from now on its reminders stay as set when its section changes (all but
    /// the travel cut-off, which follows the document). Choosing exactly the usual ones lets
    /// them follow the document again (`DeadlineReminders.isCustomized`).
    ///
    /// Only what the change made from the profile it started from (`startedFrom`, else the one
    /// stored now) is written, part by part (`ThreeWay`): a lead turned on here and the follow-up
    /// turned off meanwhile on another device both stay.
    public func setReminders(_ obligation: Obligation, _ profile: ReminderProfile, startedFrom start: ReminderProfile? = nil) throws {
        let profile = ThreeWay.laying(profile, over: obligation.reminders, startedFrom: start ?? obligation.reminders)
        obligation.reminders = profile
        obligation.remindersCustomized = DeadlineReminders.isCustomized(profile, for: obligation, in: context)
        try save()
    }

    /// The "follow up after it lapses" checkbox: the person's choice, kept like `setReminders`.
    public func setFollowUpAfterLapse(_ obligation: Obligation, _ isOn: Bool) throws {
        obligation.followUpAfterLapse = isOn
        obligation.remindersCustomized = DeadlineReminders.isCustomized(obligation.reminders, for: obligation, in: context)
        try save()
    }

    /// "Revino la cele obișnuite": a deadline whose reminders the person set gets back the ones
    /// its document gives (`DeadlineReminders.restorable`) and follows its document again.
    /// Undoable; nil when there is nothing to give back.
    @discardableResult
    public func restoreUsualReminders(_ obligation: Obligation) throws -> Undoable<ReminderProfile>? {
        guard let usual = DeadlineReminders.restorable(obligation, in: context) else { return nil }
        return try UnitOfWork.performUndoable(in: context, now: now()) {
            obligation.reminders = usual
            obligation.remindersCustomized = false
            try save()
            return usual
        }
    }

    @discardableResult
    public func reschedule(_ obligation: Obligation, to day: CalendarDay) throws -> UndoReceipt {
        try UnitOfWork.performUndoable(in: context, now: now()) {
            obligation.dueDay = day
            obligation.snoozedUntil = nil
            try save()
        }.receipt
    }

    /// What it is expected to cost and the number it quotes (a bill's amount and number).
    public func setDetails(_ obligation: Obligation, estimatedCost: Money?, reference: String?) throws {
        guard obligation.estimatedCost != estimatedCost || obligation.reference != reference else { return }
        obligation.estimatedCost = estimatedCost
        obligation.reference = reference
        try save()
    }

    /// Stops the obligation and its reminders until it is resumed. Undoable; inside a
    /// larger step (an edit that turns on direct debit), the receipt takes back that whole step.
    @discardableResult
    public func pause(_ obligation: Obligation) throws -> UndoReceipt {
        try UnitOfWork.performUndoable(in: context, now: now()) { try setStatus(.paused, of: obligation) }.receipt
    }

    /// Starts a paused obligation again. Undoable, like `pause`.
    @discardableResult
    public func resume(_ obligation: Obligation) throws -> UndoReceipt {
        try UnitOfWork.performUndoable(in: context, now: now()) { try setStatus(.active, of: obligation) }.receipt
    }

    /// Changes how the obligation repeats (a service every 150 hours instead of 100). The
    /// due day and the counter it is due at stay; the new rule counts from the next cycle.
    /// Undoable, like `pause`.
    @discardableResult
    public func setRecurrence(_ obligation: Obligation, _ rule: RecurrenceRule) throws -> UndoReceipt {
        try UnitOfWork.performUndoable(in: context, now: now()) {
            obligation.recurrence = rule
            try save()
        }.receipt
    }

    /// Puts the obligation away for good, keeping it and its history. Undoable, like `pause`.
    @discardableResult
    public func archive(_ obligation: Obligation) throws -> UndoReceipt {
        try UnitOfWork.performUndoable(in: context, now: now()) { try setStatus(.archived, of: obligation) }.receipt
    }

    /// Deletes the obligation and its reminders. What it closed stays in the section's
    /// history and its documents stay in the binder, without the link. Undoable: the
    /// receipt brings it back with every link (`UndoReceipt` reads what a delete takes).
    @discardableResult
    public func delete(_ obligation: Obligation) throws -> UndoReceipt {
        try UnitOfWork.performUndoable(in: context, now: now()) {
            context.delete(obligation)
            try save()
        }.receipt
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
        let isExample = try ExampleOwnership.requireReal(asset)
        let obligation = Obligation(
            title: title,
            kind: kind,
            dueDay: dueDay,
            recurrence: recurrence,
            reminders: reminders,
            estimatedCost: estimatedCost
        )
        obligation.provider = provider
        obligation.reference = reference
        obligation.notes = notes
        context.insert(obligation)
        obligation.asset = asset
        obligation.isExample = isExample
        try save()
        return obligation
    }

    /// Creates an obligation from a template blueprint. `firstDue` overrides the
    /// blueprint's own rule; it is required when the blueprint asks for a date.
    @discardableResult
    public func create(from blueprint: ObligationBlueprint, for asset: Asset, firstDue: CalendarDay? = nil) throws -> Obligation {
        try ExampleOwnership.requireReal(asset)
        let obligation = try HouseholdMutations.makeObligation(from: blueprint, for: asset, firstDue: firstDue, today: CalendarDay(now(), calendar: calendar), calendar: calendar, in: context)
        try save()
        return obligation
    }

    // MARK: Private

    private func setStatus(_ status: ObligationStatus, of obligation: Obligation) throws {
        obligation.status = status
        if status != .active { obligation.snoozedUntil = nil }
        try save()
    }

    private func save() throws {
        try UnitOfWork.save(context, now: now())
    }
}

extension DosarSchemaV13.Obligation {
    /// The counter unit for metric-based obligations, such as kilometres.
    public var metricUnit: MeasurementUnit? {
        if case .metric(_, let unit, _) = recurrence { return unit }
        return nil
    }
}
