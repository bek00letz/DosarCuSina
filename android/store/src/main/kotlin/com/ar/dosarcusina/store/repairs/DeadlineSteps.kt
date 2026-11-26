package com.ar.dosarcusina.store.repairs

import com.ar.dosarcusina.archive.v3.RecurrenceRule
import com.ar.dosarcusina.archive.v3.ReminderProfile
import com.ar.dosarcusina.core.values.KeptObject
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.obligations.DeadlineReminders
import com.ar.dosarcusina.store.obligations.LikelyDoubleCompletions
import com.ar.dosarcusina.store.obligations.completion
import com.ar.dosarcusina.store.obligations.dueDay
import com.ar.dosarcusina.store.obligations.recurrence
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.keptBlueprints
import com.ar.dosarcusina.store.schema.keptRecurrence
import com.ar.dosarcusina.store.schema.keptValues
import com.ar.dosarcusina.store.schema.withKeptRecurrence

// The repair list's steps over deadlines (ios/DosarCuSina/Services/Repairs/DataRepairSteps.swift,
// TravelCutoffRepairStep.swift, RenewalRepeatsStep.swift), each checking the one rule the deadline
// actions follow: LikelyDoubleCompletions, DeadlineReminders, CompletionShape.replacesDocument.

/**
 * Deadlines an old reminder button may have closed twice ([LikelyDoubleCompletions]), as the iOS app's
 * `DoubleCompletionsStep`: listed only, and the second completion deleted with the owner's OK, as Istoric
 * would, so the deadline goes back to the cycle it closed.
 */
object DoubleCompletionsStep : DataRepairStep {
    override val id = DataRepairStepId.DOUBLE_COMPLETIONS
    override val group = DataRepairGroup.DEADLINES_CLOSED_TWICE

    override fun findings(scan: DataRepairScan): List<DataRepairFinding> {
        val view = scan.view
        val obligations = view.all(Tables.obligations).associateBy { it.id }
        return LikelyDoubleCompletions.find(view, scan.context.zone).map { candidate ->
            val obligation = obligations[candidate.obligationId]
            DataRepairFinding(
                id = DataRepairFinding.id(id, RepairReading.key(candidate.historyEntryId)),
                step = id,
                subject = DataRepairSubject.DoubleCompletion(
                    candidate,
                    deadline = obligation?.title.orEmpty(),
                    section = obligation?.let { section(view, it) }.orEmpty(),
                ),
            )
        }
    }

    override fun apply(findings: List<DataRepairFinding>, step: Step, context: DataRepairContext) {
        for (subject in findings.mapNotNull { it.subject as? DataRepairSubject.DoubleCompletion }) {
            LikelyDoubleCompletions.undoSecond(step, subject.candidate, context.zone)
        }
    }
}

/**
 * A deadline whose travel margin isn't the one its document gives, as the iOS app's `TravelCutoffStep`: a
 * passport added before margins existed, a document changed from a passport to another type before
 * reminders followed the type. It checks the one rule ([DeadlineReminders.expected]) and applies it the
 * way „Editează” does ([DeadlineReminders.refresh]), so the person's own leads, grace and follow-up stay.
 * It asks, because it changes when the person is reminded. Nothing names a document type.
 */
object TravelCutoffStep : DataRepairStep {
    override val id = DataRepairStepId.TRAVEL_CUTOFF
    override val group = DataRepairGroup.PASSPORTS_AND_TRAVEL

    /** A deadline to give the reminders it follows, and those reminders. */
    private class Candidate(val obligation: Obligation, val section: String, val expected: ReminderProfile)

    private fun candidates(view: BinderView): List<Candidate> {
        val categories = RepairReading.categories(view)
        return view.all(Tables.obligations).sortedBy { it.createdAt }.mapNotNull { obligation ->
            if (obligation.isExample) return@mapNotNull null
            val asset = obligation.asset?.let { view.row(Tables.assets, it) } ?: return@mapNotNull null
            val template = categories[asset.templateKey] ?: return@mapNotNull null
            val blueprint = template.keptBlueprints.items.firstOrNull { it.key == obligation.blueprintKey }
            val expected = DeadlineReminders.expected(obligation, blueprint, asset.keptValues.value)
                ?: return@mapNotNull null
            if (obligation.travelMarginDays == expected.travelMarginDays) return@mapNotNull null
            Candidate(obligation, asset.name, expected)
        }
    }

    override fun findings(scan: DataRepairScan): List<DataRepairFinding> =
        candidates(scan.view).mapNotNull { candidate -> finding(candidate, scan) }

    private fun finding(candidate: Candidate, scan: DataRepairScan): DataRepairFinding? {
        val margin = candidate.expected.travelMarginDays
        val due = candidate.obligation.dueDay(scan.context.zone)
        val cutoff = candidate.expected.rule.urgencyRule.travelCutoff(due)
        // A margin with no cut-off before the day can't be said, so it isn't offered.
        if (candidate.expected.travelMarginDays > 0 && cutoff == null) return null
        return DataRepairFinding(
            id = DataRepairFinding.id(id, RepairReading.key(candidate.obligation.id), margin.toString()),
            step = id,
            subject = DataRepairSubject.TravelCutoff(
                obligationId = candidate.obligation.id,
                marginDays = margin,
                section = candidate.section,
                reminders = candidate.expected,
                cutoff = cutoff,
            ),
        )
    }

    override fun apply(findings: List<DataRepairFinding>, step: Step, context: DataRepairContext) {
        val approved = findings.mapNotNull { it.subject as? DataRepairSubject.TravelCutoff }
            .mapTo(mutableSetOf()) { it.obligationId to it.marginDays }
        val categories = RepairReading.categories(step)
        for (candidate in candidates(step).filter { it.obligation.id to it.expected.travelMarginDays in approved }) {
            val asset = candidate.obligation.asset?.let { step.row(Tables.assets, it) } ?: continue
            val blueprints = categories[asset.templateKey]?.keptBlueprints?.items.orEmpty()
            DeadlineReminders.refresh(step, candidate.obligation, blueprints)
        }
    }
}

/**
 * A deadline whose closing replaces a document with a new one (a personal document's renewal, a health
 * file's European health card) closes when it is done, whatever its repeat, as the iOS app's
 * `RenewalRepeatsStep`. One an earlier catalog made still repeats, so its page says it repeats though
 * closing it closes it. This finds every such deadline still kept with a repeat, by what its completion
 * does rather than by its name, and stops it repeating, asking first. A correction, not a suggestion:
 * applying it changes no reminder and no due day, only what the page says.
 */
object RenewalRepeatsStep : DataRepairStep {
    override val id = DataRepairStepId.RENEWAL_REPEATS
    override val group = DataRepairGroup.RENEWED_DOCUMENTS

    private fun candidates(view: BinderView): List<Obligation> {
        val categories = RepairReading.categories(view)
        return view.all(Tables.obligations).sortedBy { it.createdAt }.filter { obligation ->
            if (obligation.isExample || !obligation.recurrence.repeats) return@filter false
            val template = obligation.asset?.let { view.row(Tables.assets, it) }?.let { categories[it.templateKey] }
            obligation.completion(template?.keptBlueprints?.items.orEmpty()).replacesDocument
        }
    }

    override fun findings(scan: DataRepairScan): List<DataRepairFinding> = candidates(scan.view).map { obligation ->
        DataRepairFinding(
            id = DataRepairFinding.id(id, RepairReading.key(obligation.id)),
            step = id,
            subject = DataRepairSubject.StopsRepeating(
                obligationId = obligation.id,
                deadline = obligation.title,
                section = section(scan.view, obligation) ?: obligation.title,
            ),
        )
    }

    override fun apply(findings: List<DataRepairFinding>, step: Step, context: DataRepairContext) {
        val approved = findings.mapNotNull { (it.subject as? DataRepairSubject.StopsRepeating)?.obligationId }.toSet()
        // Checked again: one that no longer repeats changes nothing.
        for (obligation in candidates(step)) {
            if (obligation.id !in approved) continue
            val kept: KeptObject<RecurrenceRule> = obligation.keptRecurrence
            step.update(obligation.withKeptRecurrence(kept.replacingValue(RecurrenceRule.None)))
        }
    }
}

/** The name of the section [obligation] is in; none for a deadline of the household. */
private fun section(view: BinderView, obligation: Obligation): String? =
    obligation.asset?.let { view.row(Tables.assets, it) }?.name
