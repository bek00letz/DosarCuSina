import Foundation
import SwiftData

public enum ObligationActionError: LocalizedError, Equatable {
    /// Only active obligations can be completed or snoozed.
    case notActive
    /// The blueprint needs a date the person has to enter.
    case missingFirstDueDate(blueprintKey: String)
    /// Only a deadline of the person's own can be renamed or have its importance changed: a
    /// category's keeps the name and kind its blueprint gives (`Obligation.isPersonsOwn`).
    case notPersonsOwn
    /// A deadline needs a name.
    case missingTitle
    /// The cycle the person saw was closed meanwhile (from a reminder, the widget, Siri or
    /// another device): nothing is filed against the next one.
    case cycleClosed
    /// A new day to continue on (a kit's new expiry, a contract's new end) that isn't after
    /// today (`ObligationActions.continues(on:after:)`).
    case newDayHasPassed

    public var errorDescription: String? {
        switch self {
        case .notActive:
            return String(localized: "Obligația e pusă pe pauză sau încheiată. Reactiveaz-o mai întâi.")
        case .missingFirstDueDate:
            return String(localized: "Alege data la care e scadentă prima dată.")
        case .notPersonsOwn:
            return String(localized: "Numele și cât de important e vin din categoria lui, așa că rămân cum sunt.",
                          comment: "Error: a category's deadline can't be renamed or have its importance changed.")
        case .missingTitle:
            return String(localized: "Scrie ce trebuie făcut, apoi salvează.", comment: "Error: a deadline's name was left empty.")
        case .cycleClosed:
            return String(localized: "Termenul a fost bifat între timp, dintr-o notificare, din widget sau de pe alt dispozitiv. N-am salvat nimic, iar următorul termen a rămas cum era.",
                          comment: "Error: the deadline was closed elsewhere while the person was closing it; nothing was saved.")
        case .newDayHasPassed:
            // A fix, not a verdict, as a field's message: said under the date in "Am rezolvat".
            return String(localized: "Alege o zi de după azi. Data aceasta a trecut deja.",
                          comment: "Under a new expiry or end date that isn't after today: pick a later day.")
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
    ///
    /// - `cycle` is the cycle the person saw (the due day on the row, the page or the reminder
    ///   they acted on): when it is no longer the open one, here or in the store (closed meanwhile
    ///   from a reminder, the widget or another device), nothing is written and it throws
    ///   `cycleClosed`, so a second tap never closes the next cycle. Nil: the cycle open now, for
    ///   a step that closes whatever is due (a document filed from the review).
    /// - `continuingOn` is a new day the deadline goes on from (a new kit's expiry, a renewed
    ///   contract's end, the next date a paper prints): the completion is recorded and the
    ///   deadline stays active on that day, repeating or not. It must be after today
    ///   (`continues(on:after:)`), else it throws `newDayHasPassed`.
    ///
    /// The one way a deadline is closed: the app's sheet and quick "Gata", Urmează, and every
    /// action from outside the app (`IntentEngine`) come here.
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
        lowerReading: LowerReadingAnswer? = nil,
        cycle: CalendarDay? = nil,
        continuingOn newDay: CalendarDay? = nil
    ) throws -> Undoable<HistoryEntry> {
        guard obligation.status == .active else { throw ObligationActionError.notActive }
        try requireOpen(obligation, cycle: cycle)
        if let newDay, !Self.continues(on: newDay, after: CalendarDay(now(), calendar: calendar)) {
            throw ObligationActionError.newDayHasPassed
        }
        let completedAt = date ?? now()
        // Every question first, before anything is written (`StepQuestion`).
        let reading = plannedReading(metricReading, completing: obligation, on: completedAt)
        try HouseholdMutations.askAboutReading(reading, answer: lowerReading)
        // What the record is, from the deadline's completion kind: a rovinietă bought, a policy paid.
        let historyKind = obligation.completionHistoryKind(in: context)
        // A deadline whose closing replaces a document with a new one (a passport, a health
        // file's health card) closes, whatever its repeat: the new one reminds of its own.
        let replacesDocument = obligation.completion(in: context).replacesDocument
        return try UnitOfWork.performUndoable(in: context, now: now()) {
            let completedDay = CalendarDay(completedAt, calendar: calendar)

            let entry = HistoryEntry(kind: historyKind, title: obligation.title, occurredAt: completedAt)
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
            let next = replacesDocument ? nil : RecurrenceEngine.nextDue(
                after: obligation.dueDay,
                completedOn: completedDay,
                rule: obligation.recurrence,
                context: recurrenceContext,
                calendar: calendar
            )
            // The new day the person gave wins over the one the rule works out; a one-off with
            // one goes on from it instead of closing.
            if let day = newDay ?? next?.day {
                obligation.dueDay = day
                if let next { obligation.dueMetric = next.metric }
                entry.nextDueDay = obligation.dueDay
            } else {
                obligation.status = .done
            }
            obligation.snoozedUntil = nil
            try save()
            return entry
        }
    }

    /// The one rule for a new day a completion goes on from (a kit's new expiry, a renewed
    /// contract's end, a paper's next date): only a day after `today`. The sheet refuses an
    /// earlier one it asks, with a note under its field (`CompletionDraft.newDayProblem`), and the
    /// filer leaves out one read off a paper (`CaptureFiler`).
    nonisolated static func continues(on day: CalendarDay, after today: CalendarDay) -> Bool {
        day > today
    }

    /// Whether `cycle`, the one the person saw, is still the deadline's open one: active and due
    /// that day, in this context and in the store as it is now. A completion from another device
    /// lands in the store under the context (`SyncedChanges`), so both are read.
    func isOpen(_ obligation: Obligation, cycle: CalendarDay) throws -> Bool {
        func open(_ copy: Obligation?) -> Bool {
            guard let copy else { return false }
            return copy.status == .active && copy.dueDay == cycle
        }
        guard open(obligation) else { return false }
        let id = obligation.id
        var descriptor = FetchDescriptor<Obligation>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        // Gone from the store (deleted on another device): nothing left to close.
        return open(try PersistenceController.context(in: context.container).fetch(descriptor).first)
    }

    /// Throws `cycleClosed` when `cycle` (the one the person saw) is no longer open; nothing
    /// to check without one. Asked before a step's unit opens by a flow that completes inside
    /// a larger step (`CaptureFiler`), and again by `complete`.
    func requireOpen(_ obligation: Obligation, cycle: CalendarDay?) throws {
        guard let cycle else { return }
        guard try isOpen(obligation, cycle: cycle) else { throw ObligationActionError.cycleClosed }
    }

    /// The reading "Gata" records with the counter the person read (`metricReading`): on the
    /// deadline's section, in its counter's unit (`counter`), on the day it was done. Asked about
    /// before the step's unit opens, by `complete` and by any flow that completes inside a larger step.
    func plannedReading(_ metricReading: Double?, completing obligation: Obligation, on date: Date) -> PlannedReading? {
        guard let metricReading, let asset = obligation.asset else { return nil }
        let template = (try? TemplateStore(context: context).template(forKey: asset.templateKey)) ?? nil
        let unit = Self.counter(completing: obligation, template: template?.definition)?.unit ?? obligation.metricUnit
        return PlannedReading(metricReading, on: asset, at: date, source: .person, unit: unit)
    }

    /// The counter a completion reads ("Am rezolvat" on an oil change): the one the deadline
    /// counts on (every 15.000 km), else its section's own (a car's kilometres, a boat's engine
    /// hours); nil when there is none. The sheet asks it by this title, and the reading is
    /// recorded in this unit (`plannedReading`): the same counter either way.
    struct Counter: Equatable {
        /// The section's own name for it ("Kilometraj"), else the unit's ("km").
        let title: String
        let unit: MeasurementUnit
    }

    static func counter(completing obligation: Obligation, template: TemplateDefinition?,
                        asks: CompletionShape.Counter = .section) -> Counter? {
        let own = template.flatMap(HouseholdMutations.heroMetricField(of:))
        if let unit = obligation.metricUnit {
            return Counter(title: own.flatMap { $0.unit == unit ? $0.label : nil } ?? unit.label, unit: unit)
        }
        // Work done at home asks only the counter it counts on: one that repeats by time asks none.
        guard asks == .section, obligation.asset != nil, let own, let unit = own.unit else { return nil }
        return Counter(title: own.label, unit: unit)
    }

    /// A completion from before the binder knew the obligation (last year's ITP): logged
    /// in the history with the cycle it closed, without moving the obligation. Only the
    /// example loader uses it today, so its entry is an example exactly when the
    /// obligation is one.
    @discardableResult
    func recordPastCompletion(of obligation: Obligation, on date: Date, cost: Money?) throws -> HistoryEntry {
        let entry = HistoryEntry(kind: obligation.completionHistoryKind(in: context), title: obligation.title, occurredAt: date)
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

    /// Brings a snoozed obligation back now ("Nu mai amâna"). Undoable.
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

    /// Changes how the obligation repeats (a service every 150 hours instead of 100, watering
    /// every 3 days instead of every week). The due day and the counter it is due at stay; the
    /// new rule counts from the next cycle. Undoable, like `pause`.
    ///
    /// Only what the change made from the rule it started from (`startedFrom`, else the one
    /// stored now) is written, part by part (`ThreeWay`): the interval changed here and the
    /// anchor changed meanwhile on another device both stay.
    @discardableResult
    public func setRecurrence(_ obligation: Obligation, _ rule: RecurrenceRule, startedFrom start: RecurrenceRule? = nil) throws -> UndoReceipt {
        try UnitOfWork.performUndoable(in: context, now: now()) {
            let laid = ThreeWay.laying(rule, over: obligation.recurrence, startedFrom: start ?? obligation.recurrence)
            if laid != obligation.recurrence { obligation.recurrence = laid }
            try save()
        }.receipt
    }

    /// The time of day this deadline reminds at ("Ora amintirii"), in minutes after midnight;
    /// nil goes back to the general time in Settings, which then applies to it again whenever
    /// that changes. Synced and carried in backups like the deadline's other values; it doesn't
    /// change since when the cycle is known (`CycleTimes`). Undoable.
    ///
    /// `startedFrom` is the time the editor opened with: a time changed meanwhile on another
    /// device stays when this edit left it as it was (`ThreeWay`).
    @discardableResult
    public func setReminderTime(_ obligation: Obligation, minuteOfDay: Int?, startedFrom start: Int?) throws -> UndoReceipt {
        let minute = minuteOfDay.map(ReminderClock.clamped)
        return try UnitOfWork.performUndoable(in: context, now: now()) {
            let kept = ThreeWay.value(minute, over: obligation.reminderMinuteOfDay, startedFrom: start)
            if kept != obligation.reminderMinuteOfDay { obligation.reminderMinuteOfDay = kept }
            try save()
        }.receipt
    }


    /// A new name for a deadline of the person's own ("Udat plantele" for "Udat palntele").
    /// Undoable. A category's deadline keeps its blueprint's name (`notPersonsOwn`). What it
    /// closed before keeps the name it had then, in Istoric.
    ///
    /// `startedFrom` is the name the editor opened with: a name changed meanwhile on another
    /// device stays when this edit left it as it was (`ThreeWay`).
    @discardableResult
    func rename(_ obligation: Obligation, to title: String, startedFrom start: String? = nil) throws -> UndoReceipt {
        guard obligation.isPersonsOwn else { throw ObligationActionError.notPersonsOwn }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw ObligationActionError.missingTitle }
        return try UnitOfWork.performUndoable(in: context, now: now()) {
            let kept = ThreeWay.value(title, over: obligation.title, startedFrom: start ?? obligation.title)
            if kept != obligation.title { obligation.title = kept }
            try save()
        }.receipt
    }

    /// How important a deadline of the person's own is ("Cât de important e"), which is its kind:
    /// what closing it asks, how urgent it gets and its consequence. Its reminders follow the
    /// new kind only where the person hadn't set them (`DeadlineChoice.reminders(_:from:to:)`).
    /// Undoable. A category's deadline keeps its blueprint's kind (`notPersonsOwn`).
    ///
    /// `startedFrom` is the importance the editor opened with (`DeadlineChoice.Importance(kind:)`):
    /// one changed meanwhile on another device stays when this edit left it as it was (`ThreeWay`).
    @discardableResult
    func setImportance(_ obligation: Obligation, _ importance: DeadlineChoice.Importance,
                              startedFrom start: DeadlineChoice.Importance? = nil) throws -> UndoReceipt {
        guard obligation.isPersonsOwn else { throw ObligationActionError.notPersonsOwn }
        return try UnitOfWork.performUndoable(in: context, now: now()) {
            let stored = DeadlineChoice.Importance(kind: obligation.kind)
            let kept = ThreeWay.value(Optional(importance), over: stored, startedFrom: start ?? stored)
            if let kept, kept.kind != obligation.kind {
                let previous = obligation.kind
                obligation.kind = kept.kind
                let reminders = DeadlineChoice.reminders(obligation.reminders, from: previous, to: kept.kind)
                if reminders != obligation.reminders { obligation.reminders = reminders }
            }
            try save()
        }.receipt
    }

    /// "Editează" on a deadline's page: its name and importance (a deadline of the person's own),
    /// its due day, how it repeats, its reminders and its reminder time, saved as one undoable
    /// step. Each part goes through its own action above, inside one unit, and only the parts
    /// the person changed from what the sheet opened with (`start`) are written, each laid over
    /// what is stored now (`ThreeWay`): a part changed meanwhile on another device and left
    /// alone here stays. Nil when nothing was changed.
    @discardableResult
    func edit(_ obligation: Obligation, to edited: DeadlineEdit, startedFrom start: DeadlineEdit) throws -> UndoReceipt? {
        guard edited != start else { return nil }
        let renames = edited.title != start.title
        let changesImportance = edited.importance != nil && edited.importance != start.importance
        if (renames || changesImportance) && !obligation.isPersonsOwn { throw ObligationActionError.notPersonsOwn }
        if renames && edited.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw ObligationActionError.missingTitle }
        return try UnitOfWork.performUndoable(in: context, now: now()) {
            if renames { try rename(obligation, to: edited.title, startedFrom: start.title) }
            // Before the reminders: a new importance moves the reminders the person hadn't set,
            // and the sheet's reminders, moved by the same rule, are laid over them.
            if changesImportance, let importance = edited.importance { try setImportance(obligation, importance, startedFrom: start.importance) }
            if edited.dueDay != start.dueDay { try reschedule(obligation, to: edited.dueDay) }
            if edited.recurrence != start.recurrence { try setRecurrence(obligation, edited.recurrence, startedFrom: start.recurrence) }
            if edited.reminders != start.reminders { try setReminders(obligation, edited.reminders, startedFrom: start.reminders) }
            if edited.reminderMinuteOfDay != start.reminderMinuteOfDay {
                try setReminderTime(obligation, minuteOfDay: edited.reminderMinuteOfDay, startedFrom: start.reminderMinuteOfDay)
            }
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
        notes: String? = nil,
        reminderMinuteOfDay: Int? = nil
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
        obligation.reminderMinuteOfDay = reminderMinuteOfDay.map(ReminderClock.clamped)
        context.insert(obligation)
        obligation.asset = asset
        obligation.isExample = isExample
        try save()
        return obligation
    }

    /// Creates an obligation from a template blueprint. `firstDue` overrides the
    /// blueprint's own rule; it is required when the blueprint asks for a date.
    /// `reminderMinuteOfDay` is a reminder time of its own, nil for the general one.
    @discardableResult
    public func create(from blueprint: ObligationBlueprint, for asset: Asset, firstDue: CalendarDay? = nil, reminderMinuteOfDay: Int? = nil) throws -> Obligation {
        try ExampleOwnership.requireReal(asset)
        let obligation = try HouseholdMutations.makeObligation(from: blueprint, for: asset, firstDue: firstDue, today: CalendarDay(now(), calendar: calendar), calendar: calendar, in: context)
        obligation.reminderMinuteOfDay = reminderMinuteOfDay.map(ReminderClock.clamped)
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

extension Obligation {
    /// A deadline the person wrote themselves ("Alt termen"), not one of its category's usual
    /// ones: its name and importance are theirs to change (`ObligationActions.rename`,
    /// `setImportance`). A category's deadline keeps the name and kind its blueprint gives.
    public var isPersonsOwn: Bool { blueprintKey == nil }

    /// The counter unit for metric-based obligations, such as kilometres.
    public var metricUnit: MeasurementUnit? {
        if case .metric(_, let unit, _) = recurrence { return unit }
        return nil
    }
}
