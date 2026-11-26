package com.ar.dosarcusina.store.templates

import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.archive.v3.RecurrenceRule
import com.ar.dosarcusina.archive.v3.ReminderProfile
import com.ar.dosarcusina.catalog.BuiltInTemplates
import com.ar.dosarcusina.catalog.Catalog
import com.ar.dosarcusina.catalog.HouseholdRules
import com.ar.dosarcusina.catalog.RecurrenceEngine
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.KeptObject
import com.ar.dosarcusina.core.values.StoredDay
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.obligations.ObligationStatus
import com.ar.dosarcusina.store.obligations.status
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.dueDay
import com.ar.dosarcusina.store.schema.keptReminders
import com.ar.dosarcusina.store.schema.withKeptRecurrence
import com.ar.dosarcusina.store.schema.withKeptReminders
import java.time.Instant
import java.time.ZoneId

/**
 * The household's own deadlines kept in step with the sections that call for them, as the iOS
 * app's `HouseholdRules.reconcile` (ios/DosarCuSina/Services/Templates/HouseholdRules.swift), by the
 * shared catalog's rules ([HouseholdRules]). It runs inside a step and saves nothing itself: launch
 * runs it as the app's own step (`LaunchData.reconcileHouseholdRules`), an import inside its own
 * step (`RoomArchiveTarget`), and the actions that make or delete a section in theirs (Phase 3).
 */
class HouseholdDeadlines(
    private val rules: HouseholdRules = Catalog.builtIn.household,
    /** The time zone days are counted in: a deadline whose due day can't be read is due on the day it was made. */
    private val zone: ZoneId,
) {
    /**
     * Makes or removes the household's deadlines to match the sections in [step] on [today]; [now]
     * is when one it makes was made. Whether anything changed.
     *
     * - With no tenancy, a declaration goes only once the binder has all arrived ([binderIsWhole],
     *   `CloudArrival`) and only when nothing of the person's is on it (a completion, a document):
     *   one they filed or attached a paper to stays, as theirs.
     * - Two copies of one (each phone made its own, and "Adaugă" brought them together) become one:
     *   the copy with the person's history on it is kept ([HouseholdRules.kept]), and what the others
     *   recorded, their completions and documents, moves onto it before they go, with their notes and
     *   reminders where the kept copy has none of its own. Copies of one record (the same id) are left
     *   to the copy rule (`RecordsMeet`), which every phone follows the same way.
     * - A new declaration is made only once the binder has all arrived: the person's own may be on
     *   its way. On Android, with nothing arriving from elsewhere yet, the binder is always whole.
     */
    fun reconcile(step: Step, today: CalendarDay, now: Instant, binderIsWhole: Boolean = true): Boolean {
        val tenancies = step.all(Tables.assets).filter { it.templateKey == BuiltInTemplates.Key.TENANCY }
        val existing = step.all(Tables.obligations).filter { it.blueprintKey == HouseholdRules.RENTAL_DECLARATION_KEY }
        // Examples only produce an example declaration; one real tenancy makes it real.
        val isExample = tenancies.all { it.isExample }
        val kept = rules.kept(existing) { copy(step, it) }
        return when {
            tenancies.isEmpty() -> removeUnused(step, existing, binderIsWhole)
            kept != null -> keepOne(step, existing, kept, isExample, binderIsWhole)
            // The person's declaration may still be on its way: one made now would be a second copy.
            !binderIsWhole -> false
            else -> declaration(today, now, isExample)?.also(step::insert) != null
        }
    }

    /**
     * With no tenancy, the declarations nobody used go, once the binder has all arrived: a binder
     * still arriving may bring its tenancy later. One with something of the person's on it is their
     * record and stays: the income it declares is still due after the last tenancy ends.
     */
    private fun removeUnused(step: Step, existing: List<Obligation>, binderIsWhole: Boolean): Boolean {
        if (!binderIsWhole) return false
        val unused = existing.filter { !isFiled(step, it) && !hasDocuments(step, it) }
        unused.forEach(step::delete)
        return unused.isNotEmpty()
    }

    /**
     * [kept] the one copy, the others folded into it once the binder has all arrived; an example
     * while every tenancy is.
     */
    private fun keepOne(
        step: Step,
        existing: List<Obligation>,
        kept: Obligation,
        isExample: Boolean,
        binderIsWhole: Boolean,
    ): Boolean {
        var changed = false
        val distinct = existing.map { it.id }.toSet().size == existing.size
        if (existing.size > 1 && distinct && binderIsWhole) {
            var staying = kept
            for (extra in existing) {
                if (extra.pk == kept.pk) continue
                staying = fold(step, extra, into = staying)
                step.delete(requireNotNull(step.row(Tables.obligations, extra.pk)))
                changed = true
            }
            step.update(staying)
        }
        val current = requireNotNull(step.row(Tables.obligations, kept.pk))
        if (current.isExample != isExample) {
            step.update(current.copy(isExample = isExample))
            changed = true
        }
        return changed
    }

    /** A new rental income declaration, first due by its blueprint's rule on [today]. */
    private fun declaration(today: CalendarDay, now: Instant, isExample: Boolean): Obligation? {
        val blueprint = rules.rentalDeclaration
        val due = RecurrenceEngine.firstDue(blueprint, FieldValues(), today) ?: return null
        val recurrence = blueprint.recurrence?.let(RecurrenceRule.codec::decode) ?: RecurrenceRule.None
        val reminders = blueprint.reminders?.let(ReminderProfile.codec::decode) ?: return null
        return Obligation(
            title = blueprint.title,
            kindRaw = blueprint.kind,
            dueDayISO = StoredDay.text(due),
            blueprintKey = blueprint.key,
            notes = blueprint.note,
            isExample = isExample,
            createdAt = now,
            updatedAt = now,
        ).withKeptRecurrence(KeptObject.made(recurrence, RecurrenceRule.codec))
            .withKeptReminders(KeptObject.made(reminders, ReminderProfile.codec))
    }

    /**
     * [into] with what [copy] recorded moved onto it (its completions and the documents filed with
     * it), so nothing of the person's goes with the copy; its note and the reminders the person chose
     * come too where [into] has none of its own, and its snooze when both are for the same day.
     */
    private fun fold(step: Step, copy: Obligation, into: Obligation): Obligation {
        for (entry in step.all(Tables.history).filter { it.obligation == copy.pk }) {
            step.update(entry.copy(obligation = into.pk))
        }
        for (document in step.all(Tables.attachments).filter { it.obligation == copy.pk }) {
            step.update(document.copy(obligation = into.pk))
        }
        var kept = into
        if (rules.hasOwnNote(copy.notes) && !rules.hasOwnNote(kept.notes)) kept = kept.copy(notes = copy.notes)
        if (copy.remindersCustomized && !kept.remindersCustomized) {
            kept = kept.withKeptReminders(copy.keptReminders).copy(remindersCustomized = true)
        }
        if (kept.reminderMinuteOfDay == null && copy.reminderMinuteOfDay != null) {
            kept = kept.copy(reminderMinuteOfDay = copy.reminderMinuteOfDay)
        }
        if (kept.snoozedUntilISO == null && day(kept) == day(copy) && copy.snoozedUntilISO != null) {
            kept = kept.copy(snoozedUntilISO = copy.snoozedUntilISO)
        }
        return kept
    }

    private fun copy(step: Step, obligation: Obligation) = HouseholdRules.Copy(
        id = obligation.id,
        dueDay = day(obligation),
        isOpen = obligation.status == ObligationStatus.ACTIVE,
        isFiled = isFiled(step, obligation),
        hasDocuments = hasDocuments(step, obligation),
        notes = obligation.notes,
        isSnoozed = obligation.snoozedUntilISO != null,
        remindersCustomized = obligation.remindersCustomized,
        hasOwnReminderTime = obligation.reminderMinuteOfDay != null,
    )

    /** Its due day; one that can't be read is the day it was made. */
    private fun day(obligation: Obligation): CalendarDay =
        obligation.dueDay ?: CalendarDay.of(obligation.createdAt, zone)

    private fun isFiled(step: Step, obligation: Obligation): Boolean =
        step.pointingAt(Tables.history, "obligation", obligation.pk).isNotEmpty()

    private fun hasDocuments(step: Step, obligation: Obligation): Boolean =
        step.pointingAt(Tables.attachments, "obligation", obligation.pk).isNotEmpty()
}
