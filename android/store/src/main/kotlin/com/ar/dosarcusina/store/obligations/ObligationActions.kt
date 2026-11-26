package com.ar.dosarcusina.store.obligations

import com.ar.dosarcusina.core.deadlines.defaultProfile
import com.ar.dosarcusina.core.values.ObligationKind
import com.ar.dosarcusina.archive.v3.ObligationBlueprint
import com.ar.dosarcusina.archive.v3.RecurrenceRule
import com.ar.dosarcusina.archive.v3.ReminderProfile
import com.ar.dosarcusina.catalog.Catalog
import com.ar.dosarcusina.catalog.RecurrenceEngine
import com.ar.dosarcusina.core.deadlines.HistoryKind
import com.ar.dosarcusina.core.readings.LowerReadingAnswer
import com.ar.dosarcusina.core.reminders.ReminderClock
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.DosarCalendar
import com.ar.dosarcusina.core.values.KeptObject
import com.ar.dosarcusina.core.values.Money
import com.ar.dosarcusina.core.values.ObligationStatus
import com.ar.dosarcusina.core.values.StoredDay
import com.ar.dosarcusina.core.values.ThreeWay
import com.ar.dosarcusina.store.BinderSnapshot
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.UndoReceipt
import com.ar.dosarcusina.store.Undoable
import com.ar.dosarcusina.store.UnitOfWork
import com.ar.dosarcusina.store.examples.ExampleOwnership
import com.ar.dosarcusina.store.history.HistoryActions
import com.ar.dosarcusina.store.readings.HouseholdReadings
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.Provider
import com.ar.dosarcusina.store.schema.keptRecurrence
import com.ar.dosarcusina.store.schema.keptReminders
import com.ar.dosarcusina.store.schema.reminders
import com.ar.dosarcusina.store.schema.withKeptRecurrence
import com.ar.dosarcusina.store.schema.withKeptReminders
import kotlinx.coroutines.runBlocking
import java.time.Instant
import java.time.ZoneId

/** Why a deadline action was refused, as kinds: the screens word them (Phase 4), as the iOS `ObligationActionError`. */
sealed class ObligationActionError(message: String) : Exception(message) {
    /** Only an active deadline can be completed or snoozed. */
    class NotActive : ObligationActionError("The deadline is paused or closed")

    /** The blueprint needs a date the person has to enter. */
    class MissingFirstDueDate(val blueprintKey: String) : ObligationActionError("The first due day is to be asked")

    /**
     * Only a deadline of the person's own can be renamed or have its importance changed: a category's
     * keeps the name and kind its blueprint gives ([isPersonsOwn]).
     */
    class NotPersonsOwn : ObligationActionError("A category's deadline keeps its name and kind")

    /** A deadline needs a name. */
    class MissingTitle : ObligationActionError("A deadline needs a name")

    /**
     * The cycle the person saw was closed meanwhile (from a reminder, a widget, the assistant or another
     * device): nothing is filed against the next one.
     */
    class CycleClosed : ObligationActionError("The cycle was closed meanwhile")

    /** A new day to continue on that isn't after today ([ObligationActions.continues]). */
    class NewDayHasPassed : ObligationActionError("The new day has passed")
}

/**
 * The one way a deadline changes, as the iOS app's `ObligationActions`
 * (ios/DosarCuSina/Services/Obligations/ObligationActions.swift): Urmează, a section's page, a reminder's
 * buttons, widgets and the assistant all come here. Each action saves once through the unit of work,
 * which joins a step it runs inside (a category's edit pausing its service deadlines); the side effects
 * follow from the save. An action the person can take back returns its [UndoReceipt].
 *
 * Every question comes first, before the unit of work opens (a lower counter, something of theirs in an
 * example: [HouseholdReadings.askAboutReading], [ExampleOwnership.requireReal]); every refusal is checked
 * against the binder as it is in the step, so a step that refuses has written nothing.
 */
// The iOS action's whole surface, one function per job.
@Suppress("TooManyFunctions")
class ObligationActions(
    private val unit: UnitOfWork,
    /** The step's clock: the change time it gives, and today. */
    private val now: () -> Instant = unit.clock,
    /** The time zone the app counts days in. */
    private val zone: () -> ZoneId = DosarCalendar::zone,
    /** The app's own categories: the household's deadlines and an example's question. */
    private val builtIns: Catalog = Catalog.builtIn,
) {
    // Complete

    /**
     * Records that [obligation] was done and moves it to its next cycle, or closes it when it doesn't
     * repeat. The record goes into its section's history ([HistoryActions.recordCompletion]), the same
     * history repairs and visits go into, as the kind of record its completion states. The receipt takes
     * it all back, the reading it recorded included; deleting an older completion from Istoric is
     * [HistoryActions.delete].
     *
     * - [cycle] is the cycle the person saw (the due day on the row, the page or the reminder they acted
     *   on): when it is no longer the open one in the binder (closed meanwhile from a reminder, a widget or
     *   another device), nothing is written and it throws [ObligationActionError.CycleClosed], so a second
     *   tap never closes the next cycle. Null: the cycle open now.
     * - [continuingOn] is a new day the deadline goes on from (a new kit's expiry, a renewed contract's
     *   end): the completion is recorded and the deadline stays active on that day, repeating or not. It
     *   must be after today ([continues]), else it throws [ObligationActionError.NewDayHasPassed].
     * - A deadline whose closing replaces a document with a new one closes, whatever its repeat.
     * - A [metricReading] is recorded on the section through the one reading path, asked about first
     *   ([lowerReading] answers a lower counter).
     *
     * The line items a visit's completion files with it come with the visit form's port.
     */
    @Suppress("LongParameterList") // What „Am rezolvat” asks, as the iOS action takes it.
    fun complete(
        obligation: Obligation,
        on: Instant? = null,
        cost: Money? = null,
        metricReading: Double? = null,
        note: String? = null,
        providers: List<Provider> = emptyList(),
        rating: Int? = null,
        lowerReading: LowerReadingAnswer? = null,
        cycle: CalendarDay? = null,
        continuingOn: CalendarDay? = null,
    ): Undoable<HistoryEntry> {
        val zone = zone()
        val view = snapshot()
        val current = current(view, obligation)
        requireActive(current)
        requireOpen(current, cycle)
        requireNewDay(continuingOn, zone)
        val completedAt = on ?: now()
        // Every question first, before anything is written (`StepQuestion`).
        val reading = DeadlineMutations.plannedReading(view, metricReading, current, completedAt)
        HouseholdReadings.askAboutReading(view, reading, lowerReading)
        val completion = DeadlineCategory.completionKind(view, current)
        return unit.performUndoable(now()) { step ->
            val row = fresh(step, obligation)
            // Read again in the step: a cycle closed meanwhile is never closed twice.
            requireActive(row)
            requireOpen(row, cycle)
            val due = row.dueDay(zone)
            var entry = HistoryActions.recordCompletion(
                step, row, HistoryKind.forCompleting(completion), due, completedAt,
                cost = cost, metricReading = metricReading, note = note, rating = rating,
                providers = providers.map { it.pk },
            )
            if (reading != null) HouseholdReadings.recordReading(step, reading, lowerReading, isExample = row.isExample)
            val context = DeadlineMutations.recurrenceContext(step, row, metricReading, zone, builtIns)
            val next = if (completion.shape.replacesDocument) {
                null
            } else {
                RecurrenceEngine.nextDue(due, CalendarDay.of(completedAt, zone), row.recurrence, context, zone)
            }
            // The new day the person gave wins over the one the rule works out; a one-off with one goes
            // on from it instead of closing.
            val day = continuingOn ?: next?.day
            val moved = if (day != null) {
                row.copy(dueDayISO = StoredDay.text(day), dueMetric = if (next != null) next.metric else row.dueMetric)
            } else {
                row.copy(statusRaw = ObligationStatus.DONE.raw)
            }
            step.update(moved.copy(snoozedUntilISO = null))
            if (day != null) entry = HistoryActions.closed(step, entry, day)
            entry
        }
    }

    /**
     * Whether [cycle], the one the person saw, is still [obligation]'s open one: active and due that day,
     * in the binder as it is now (a completion from another device lands in the store).
     */
    fun isOpen(obligation: Obligation, cycle: CalendarDay): Boolean {
        val stored = snapshot().row(Tables.obligations, obligation.pk) ?: return false
        return isOpenIn(stored, cycle)
    }

    /**
     * Throws [ObligationActionError.CycleClosed] when [cycle] (the one the person saw) is no longer open;
     * nothing to check without one. Asked by a flow that completes inside a larger step before its unit
     * opens, and again by [complete].
     */
    fun requireOpen(obligation: Obligation, cycle: CalendarDay?) {
        if (cycle == null) return
        if (!isOpenIn(obligation, cycle)) throw ObligationActionError.CycleClosed()
    }

    /** Throws [ObligationActionError.NotActive] for a deadline paused or closed: only an active one is completed. */
    private fun requireActive(obligation: Obligation) {
        if (obligation.status != ObligationStatus.ACTIVE) throw ObligationActionError.NotActive()
    }

    /** Throws [ObligationActionError.NewDayHasPassed] for a new day that isn't after today ([continues]). */
    private fun requireNewDay(day: CalendarDay?, zone: ZoneId) {
        if (day != null && !continues(day, CalendarDay.of(now(), zone))) throw ObligationActionError.NewDayHasPassed()
    }

    private fun isOpenIn(obligation: Obligation, cycle: CalendarDay): Boolean =
        obligation.status == ObligationStatus.ACTIVE && obligation.dueDay(zone()) == cycle

    /**
     * A completion from before the binder knew the deadline (last year's ITP): logged in the history with
     * the cycle it closed, without moving the deadline. Only the example loader uses it, so its record is
     * an example exactly when the deadline is one.
     */
    fun recordPastCompletion(obligation: Obligation, on: Instant, cost: Money?): HistoryEntry {
        val zone = zone()
        val view = snapshot()
        val completion = DeadlineCategory.completionKind(view, current(view, obligation))
        return unit.perform(now = now()) { step ->
            val row = fresh(step, obligation)
            // What it was before is a deadline running as it does now, at no counter.
            val before = row.copy(statusRaw = ObligationStatus.ACTIVE.raw, dueMetric = null)
            val entry = HistoryActions.recordCompletion(
                step, before, HistoryKind.forCompleting(completion), CalendarDay.of(on, zone), on, cost = cost,
            )
            HistoryActions.closed(step, entry, row.dueDay(zone))
        }
    }

    // Schedule

    /** Hides the deadline and its reminders for [days] days, then reminds once. Undoable. */
    fun snooze(obligation: Obligation, days: Int): UndoReceipt = unit.performUndoable(now()) { step ->
        val row = fresh(step, obligation)
        requireActive(row)
        val today = CalendarDay.of(now(), zone())
        step.update(row.copy(snoozedUntilISO = StoredDay.text(today.addingDays(maxOf(1, days)))))
    }.receipt

    /** Brings a snoozed deadline back now („Nu mai amâna”). Undoable. */
    fun clearSnooze(obligation: Obligation): UndoReceipt = unit.performUndoable(now()) { step ->
        step.update(fresh(step, obligation).copy(snoozedUntilISO = null))
    }.receipt

    /** Moves the deadline to [day], its snooze let go. Undoable. */
    fun reschedule(obligation: Obligation, day: CalendarDay): UndoReceipt = unit.performUndoable(now()) { step ->
        reschedule(step, obligation, day)
    }.receipt

    private fun reschedule(step: Step, obligation: Obligation, day: CalendarDay) {
        step.update(fresh(step, obligation).copy(dueDayISO = StoredDay.text(day), snoozedUntilISO = null))
    }

    /**
     * Changes how the deadline reminds (its leads, grace, follow-up after lapsing), as the person chose:
     * from now on its reminders stay as set when its section changes (all but the travel cut-off, which
     * follows the document). Choosing exactly the usual ones lets them follow the document again
     * ([DeadlineReminders.isCustomized]).
     *
     * Only what the change made from the profile it started from ([startedFrom], else the one stored now)
     * is written, part by part ([ThreeWay]): a lead turned on here and the follow-up turned off meanwhile on
     * another device both stay.
     */
    fun setReminders(obligation: Obligation, profile: ReminderProfile, startedFrom: ReminderProfile? = null) {
        unit.perform(now = now()) { step -> setReminders(step, obligation, profile, startedFrom) }
    }

    private fun setReminders(
        step: Step,
        obligation: Obligation,
        profile: ReminderProfile,
        startedFrom: ReminderProfile?,
    ) {
        val row = fresh(step, obligation)
        val stored = row.reminders
        val laid = ThreeWay.laying(profile, stored, startedFrom ?: stored, ReminderProfile.codec)
        val written = row.withKeptReminders(row.keptReminders.replacingValue(laid))
        step.update(written.copy(remindersCustomized = DeadlineReminders.isCustomized(step, laid, written)))
    }

    /** The „follow up after it lapses” checkbox: the person's choice, kept like [setReminders]. */
    fun setFollowUpAfterLapse(obligation: Obligation, isOn: Boolean) {
        unit.perform(now = now()) { step ->
            val row = fresh(step, obligation).copy(followUpAfterLapse = isOn)
            step.update(row.copy(remindersCustomized = DeadlineReminders.isCustomized(step, row.reminders, row)))
        }
    }

    /**
     * „Revino la cele obișnuite”: a deadline whose reminders the person set gets back the ones its document
     * gives ([DeadlineReminders.restorable]) and follows its document again. Undoable; null when there is
     * nothing to give back.
     */
    fun restoreUsualReminders(obligation: Obligation): Undoable<ReminderProfile>? {
        val view = snapshot()
        val usual = DeadlineReminders.restorable(view, current(view, obligation)) ?: return null
        return unit.performUndoable(now()) { step ->
            val row = fresh(step, obligation)
            val given = row.withKeptReminders(row.keptReminders.replacingValue(usual))
            step.update(given.copy(remindersCustomized = false))
            usual
        }
    }

    /** What it is expected to cost and the number it quotes (a bill's amount and number). */
    fun setDetails(obligation: Obligation, estimatedCost: Money?, reference: String?) {
        unit.perform(now = now()) { step ->
            val row = fresh(step, obligation)
            step.update(
                row.copy(
                    estimatedCostAmount = estimatedCost?.amount,
                    estimatedCostCurrency = estimatedCost?.currency,
                    reference = reference,
                ),
            )
        }
    }

    /**
     * Stops the deadline and its reminders until it is resumed. Undoable; inside a larger step (an edit
     * that turns on direct debit), the receipt takes back that whole step.
     */
    fun pause(obligation: Obligation): UndoReceipt =
        unit.performUndoable(now()) { step -> setStatus(step, obligation, ObligationStatus.PAUSED) }.receipt

    /** Starts a paused deadline again. Undoable, like [pause]. */
    fun resume(obligation: Obligation): UndoReceipt =
        unit.performUndoable(now()) { step -> setStatus(step, obligation, ObligationStatus.ACTIVE) }.receipt

    /** Puts the deadline away for good, keeping it and its history. Undoable, like [pause]. */
    fun archive(obligation: Obligation): UndoReceipt =
        unit.performUndoable(now()) { step -> setStatus(step, obligation, ObligationStatus.ARCHIVED) }.receipt

    /**
     * Deletes the deadline and its reminders. What it closed stays in the section's history and its
     * documents stay in the binder, without the link. Undoable: the receipt brings it back with every link.
     */
    fun delete(obligation: Obligation): UndoReceipt = unit.performUndoable(now()) { step ->
        step.delete(fresh(step, obligation))
    }.receipt

    /**
     * Changes how the deadline repeats (a service every 150 hours instead of 100). The due day and the
     * counter it is due at stay; the new rule counts from the next cycle. Undoable.
     *
     * Only what the change made from the rule it started from ([startedFrom], else the one stored now) is
     * written, part by part ([ThreeWay]): an interval changed here and an anchor changed meanwhile both stay.
     */
    fun setRecurrence(obligation: Obligation, rule: RecurrenceRule, startedFrom: RecurrenceRule? = null): UndoReceipt =
        unit.performUndoable(now()) { step -> setRecurrence(step, obligation, rule, startedFrom) }.receipt

    private fun setRecurrence(step: Step, obligation: Obligation, rule: RecurrenceRule, startedFrom: RecurrenceRule?) {
        val row = fresh(step, obligation)
        val kept = row.keptRecurrence
        val laid = ThreeWay.laying(rule, kept.value, startedFrom ?: kept.value, RecurrenceRule.codec)
        if (laid != kept.value) step.update(row.withKeptRecurrence(kept.replacingValue(laid)))
    }

    /**
     * The time of day this deadline reminds at („Ora amintirii”), in minutes after midnight; null goes back
     * to the general time in Settings. It doesn't change since when the cycle is known. Undoable.
     *
     * [startedFrom] is the time the editor opened with: a time changed meanwhile on another device stays
     * when this edit left it as it was ([ThreeWay]).
     */
    fun setReminderTime(obligation: Obligation, minuteOfDay: Int?, startedFrom: Int?): UndoReceipt =
        unit.performUndoable(now()) { step -> setReminderTime(step, obligation, minuteOfDay, startedFrom) }.receipt

    private fun setReminderTime(step: Step, obligation: Obligation, minuteOfDay: Int?, startedFrom: Int?) {
        val row = fresh(step, obligation)
        val kept = ThreeWay.value(minuteOfDay?.let(ReminderClock::clamped), row.reminderMinuteOfDay, startedFrom)
        if (kept != row.reminderMinuteOfDay) step.update(row.copy(reminderMinuteOfDay = kept))
    }

    /**
     * A new name for a deadline of the person's own. Undoable. A category's deadline keeps its blueprint's
     * name ([ObligationActionError.NotPersonsOwn]). What it closed before keeps the name it had then.
     *
     * [startedFrom] is the name the editor opened with: a name changed meanwhile on another device stays
     * when this edit left it as it was ([ThreeWay]).
     */
    fun rename(obligation: Obligation, title: String, startedFrom: String? = null): UndoReceipt =
        unit.performUndoable(now()) { step -> rename(step, obligation, title, startedFrom) }.receipt

    private fun rename(step: Step, obligation: Obligation, title: String, startedFrom: String?) {
        val row = fresh(step, obligation)
        if (!row.isPersonsOwn) throw ObligationActionError.NotPersonsOwn()
        val name = title.trim()
        if (name.isEmpty()) throw ObligationActionError.MissingTitle()
        val kept = ThreeWay.value(name, row.title, startedFrom ?: row.title)
        if (kept != row.title) step.update(row.copy(title = kept))
    }

    /**
     * How important a deadline of the person's own is („Cât de important e”), which is its kind: what
     * closing it asks, how urgent it gets and its consequence. Its reminders follow the new kind only where
     * the person hadn't set them ([DeadlineChoice.reminders]). Undoable. A category's deadline keeps its
     * blueprint's kind ([ObligationActionError.NotPersonsOwn]).
     *
     * [startedFrom] is the importance the editor opened with: one changed meanwhile on another device stays
     * when this edit left it as it was ([ThreeWay]).
     */
    fun setImportance(
        obligation: Obligation,
        importance: DeadlineChoice.Importance,
        startedFrom: DeadlineChoice.Importance? = null,
    ): UndoReceipt =
        unit.performUndoable(now()) { step -> setImportance(step, obligation, importance, startedFrom) }.receipt

    private fun setImportance(
        step: Step,
        obligation: Obligation,
        importance: DeadlineChoice.Importance,
        startedFrom: DeadlineChoice.Importance?,
    ) {
        val row = fresh(step, obligation)
        if (!row.isPersonsOwn) throw ObligationActionError.NotPersonsOwn()
        val stored = DeadlineChoice.Importance.of(row.kind)
        val kept = ThreeWay.value<DeadlineChoice.Importance?>(importance, stored, startedFrom ?: stored) ?: return
        if (kept.kind == row.kind) return
        val reminders = DeadlineChoice.reminders(row.reminders, row.kind, kept.kind)
        val moved = row.copy(kindRaw = kept.kind.raw)
        if (reminders == row.reminders) {
            step.update(moved)
        } else {
            step.update(moved.withKeptReminders(moved.keptReminders.replacingValue(reminders)))
        }
    }

    /**
     * „Editează” on a deadline's page: its name and importance (a deadline of the person's own), its due
     * day, how it repeats, its reminders and its reminder time, saved as one undoable step. Each part goes
     * through its own action above, inside one unit, and only the parts the person changed from what the
     * sheet opened with ([startedFrom]) are written, each laid over what is stored now ([ThreeWay]). Null
     * when nothing was changed.
     */
    fun edit(obligation: Obligation, edited: DeadlineEdit, startedFrom: DeadlineEdit): UndoReceipt? {
        if (edited == startedFrom) return null
        val renames = edited.title != startedFrom.title
        val importance = edited.importance?.takeIf { it != startedFrom.importance }
        val stored = current(snapshot(), obligation)
        if ((renames || importance != null) && !stored.isPersonsOwn) throw ObligationActionError.NotPersonsOwn()
        if (renames && edited.title.isBlank()) throw ObligationActionError.MissingTitle()
        return unit.performUndoable(now()) { step ->
            if (renames) rename(step, obligation, edited.title, startedFrom.title)
            // Before the reminders: a new importance moves the reminders the person hadn't set, and the
            // sheet's reminders, moved by the same rule, are laid over them.
            if (importance != null) setImportance(step, obligation, importance, startedFrom.importance)
            if (edited.dueDay != startedFrom.dueDay) reschedule(step, obligation, edited.dueDay)
            if (edited.recurrence != startedFrom.recurrence) {
                setRecurrence(step, obligation, edited.recurrence, startedFrom.recurrence)
            }
            if (edited.reminders != startedFrom.reminders) {
                setReminders(step, obligation, edited.reminders, startedFrom.reminders)
            }
            if (edited.reminderMinuteOfDay != startedFrom.reminderMinuteOfDay) {
                setReminderTime(step, obligation, edited.reminderMinuteOfDay, startedFrom.reminderMinuteOfDay)
            }
        }.receipt
    }

    // Create

    /**
     * A new deadline of the person's own ([kind] from its importance) under [asset] (none: the
     * household's), reminding as [reminders] says, else as its kind does. Asks first when it would be the
     * person's own inside an example.
     */
    @Suppress("LongParameterList") // A new deadline's parts, as the iOS action takes them.
    fun create(
        title: String,
        kind: ObligationKind,
        dueDay: CalendarDay,
        asset: Asset?,
        recurrence: RecurrenceRule = RecurrenceRule.None,
        reminders: ReminderProfile? = null,
        estimatedCost: Money? = null,
        provider: String? = null,
        reference: String? = null,
        notes: String? = null,
        reminderMinuteOfDay: Int? = null,
    ): Obligation {
        val view = snapshot()
        val section = asset?.let { current(view, it) }
        val isExample = ExampleOwnership.requireReal(view, section, builtIns)
        val made = now()
        return unit.perform(now = made) { step ->
            step.insert(
                Obligation(
                    title = title,
                    kindRaw = kind.raw,
                    dueDayISO = StoredDay.text(dueDay),
                    estimatedCostAmount = estimatedCost?.amount,
                    estimatedCostCurrency = estimatedCost?.currency,
                    provider = provider,
                    reference = reference,
                    notes = notes,
                    reminderMinuteOfDay = reminderMinuteOfDay?.let(ReminderClock::clamped),
                    isExample = isExample,
                    asset = section?.pk,
                    createdAt = made,
                    updatedAt = made,
                ).withKeptRecurrence(KeptObject.made(recurrence, RecurrenceRule.codec))
                    .withKeptReminders(
                        KeptObject.made(reminders ?: ReminderProfile.of(kind.defaultProfile), ReminderProfile.codec),
                    ),
            )
        }
    }

    /**
     * A deadline from one of its category's usual ones ([blueprint]) under [asset]. [firstDue] overrides
     * the blueprint's own rule; it is required when the blueprint asks for a date
     * ([ObligationActionError.MissingFirstDueDate]). [reminderMinuteOfDay] is a reminder time of its own,
     * null for the general one.
     */
    fun create(
        blueprint: ObligationBlueprint,
        asset: Asset,
        firstDue: CalendarDay? = null,
        reminderMinuteOfDay: Int? = null,
    ): Obligation {
        val view = snapshot()
        val section = current(view, asset)
        ExampleOwnership.requireReal(view, section, builtIns)
        val made = now()
        return unit.perform(now = made) { step ->
            val today = CalendarDay.of(made, zone())
            val obligation = DeadlineMutations.makeObligation(step, blueprint, section, firstDue, today, made, builtIns)
            val timed = obligation.copy(reminderMinuteOfDay = reminderMinuteOfDay?.let(ReminderClock::clamped))
            step.update(timed)
            timed
        }
    }

    // Private

    private fun setStatus(step: Step, obligation: Obligation, status: ObligationStatus) {
        val row = fresh(step, obligation)
        val snoozed = if (status == ObligationStatus.ACTIVE) row.snoozedUntilISO else null
        step.update(row.copy(statusRaw = status.raw, snoozedUntilISO = snoozed))
    }

    private fun snapshot(): BinderView = runBlocking { BinderSnapshot.read(unit.store.database) }

    private fun current(view: BinderView, obligation: Obligation): Obligation =
        view.row(Tables.obligations, obligation.pk) ?: throw NoSuchElementException("The deadline isn't in the binder")

    private fun current(view: BinderView, asset: Asset): Asset =
        view.row(Tables.assets, asset.pk) ?: throw NoSuchElementException("The section isn't in the binder")

    private fun fresh(step: Step, obligation: Obligation): Obligation =
        step.row(Tables.obligations, obligation.pk) ?: throw NoSuchElementException("The deadline isn't in the binder")

    companion object {
        /**
         * The one rule for a new day a completion goes on from (a kit's new expiry, a renewed contract's
         * end, a paper's next date): only a day after [today].
         */
        fun continues(day: CalendarDay, today: CalendarDay): Boolean = day > today
    }
}
