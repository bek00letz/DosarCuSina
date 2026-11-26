package com.ar.dosarcusina.store.history

import com.ar.dosarcusina.core.deadlines.HistoryKind
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.Money
import com.ar.dosarcusina.core.values.ObligationStatus
import com.ar.dosarcusina.core.values.StoredDay
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.UnitOfWork
import com.ar.dosarcusina.store.readings.HouseholdReadings
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.Obligation
import java.time.Instant

/**
 * Logging what happened to a section, as the iOS app's `HistoryActions`
 * (ios/DosarCuSina/Services/History/HistoryActions.swift): the one way a record of history is written
 * and deleted. Completing a deadline writes its record here ([recordCompletion], from
 * `ObligationActions.complete`), in the same history repairs and visits go into.
 *
 * This is its start, what deadlines need: a completion's record and deleting a record from Istoric
 * ([delete], which moves a deadline back when its latest completion goes). Visits, repairs, purchases,
 * line items, notes and ratings come with the visit form's port and extend this class, never a second one.
 */
class HistoryActions(
    private val unit: UnitOfWork,
    /** The step's clock: the change time it gives. */
    private val now: () -> Instant = unit.clock,
) {
    /**
     * Deletes [entry] from Istoric, doing exactly what [HistoryDeletion] says: its parts and the reading
     * it recorded go, the documents filed with it stay in the binder, and a deadline's latest completion
     * moves it back to the cycle it closed. One step, saved once.
     */
    fun delete(entry: HistoryEntry) {
        unit.perform(now = now()) { step -> delete(step, entry) }
    }

    companion object {
        /** The highest rating a job gets. */
        private const val BEST_RATING = 5

        /**
         * Writes the record of [obligation]'s completion in [step], as the iOS `complete` does: [kind]
         * (its completion's record), the cycle it closed and what it was before (to go back to it), what it
         * cost, the reading, a note and a rating, under its section, an example when the deadline is one.
         * Who did the work is linked by row ([providers]). The day it moved to is set by the caller
         * ([closed]) once it is known.
         */
        @Suppress("LongParameterList") // A completion's parts, as the iOS action takes them.
        fun recordCompletion(
            step: Step,
            obligation: Obligation,
            kind: HistoryKind,
            cycle: CalendarDay,
            occurredAt: Instant,
            cost: Money? = null,
            metricReading: Double? = null,
            note: String? = null,
            rating: Int? = null,
            providers: List<Long> = emptyList(),
        ): HistoryEntry {
            val entry = step.insert(
                HistoryEntry(
                    kindRaw = kind.raw,
                    title = obligation.title,
                    occurredAt = occurredAt,
                    cycleDueDayISO = StoredDay.text(cycle),
                    previousStatusRaw = obligation.statusRaw,
                    previousDueMetric = obligation.dueMetric,
                    totalCostAmount = cost?.amount,
                    totalCostCurrency = cost?.currency,
                    metricReading = metricReading,
                    note = note,
                    rating = rating?.coerceIn(1, BEST_RATING),
                    isExample = obligation.isExample,
                    obligation = obligation.pk,
                    asset = obligation.asset,
                ),
            )
            if (providers.isNotEmpty()) step.setLinked(Tables.entryProviders, entry.pk, providers)
            return entry
        }

        /** [entry] with the day its deadline moved to, written in [step]. */
        fun closed(step: Step, entry: HistoryEntry, next: CalendarDay?): HistoryEntry {
            val written = entry.copy(nextDueDayISO = next?.let(StoredDay::text))
            step.update(written)
            return written
        }

        /** Deletes [entry] in [step], as [HistoryActions.delete] does: inside a larger step (a repair). */
        fun delete(step: Step, entry: HistoryEntry) {
            val current = step.row(Tables.history, entry.pk) ?: return
            val effect = HistoryDeletion.of(step, current)
            val reopened = effect.reopensCycle
            val owner = current.obligation?.let { step.row(Tables.obligations, it) }
            if (reopened != null && owner != null) {
                val status = ObligationStatus.stored(owner.statusRaw)
                val back = if (status == ObligationStatus.DONE) {
                    ObligationStatus.entries.firstOrNull { it.raw == current.previousStatusRaw }
                        ?: ObligationStatus.ACTIVE
                } else {
                    status
                }
                step.update(
                    owner.copy(
                        dueDayISO = StoredDay.text(reopened),
                        dueMetric = current.previousDueMetric,
                        statusRaw = if (back == status) owner.statusRaw else back.raw,
                    ),
                )
            }
            if (effect.removedReading != null) HouseholdReadings.removeReading(step, current)
            for (row in step.pointingAt(Tables.attachments, "historyEntry", current.pk)) {
                step.row(Tables.attachments, row)?.let { step.update(it.copy(historyEntry = null)) }
            }
            step.row(Tables.history, current.pk)?.let(step::delete)
        }

        /**
         * The completions of [obligation], newest first, as the iOS `Obligation.history`: two recorded at
         * the same moment are ordered by the cycle they closed, which only moves forward.
         */
        fun history(view: BinderView, obligation: Obligation): List<HistoryEntry> =
            view.pointingAt(Tables.history, "obligation", obligation.pk)
                .mapNotNull { view.row(Tables.history, it) }
                .sortedWith(newestFirst)

        /**
         * The completion the deadline's current cycle comes from, as the iOS `Obligation.latestCompletion`:
         * the one that closed the latest cycle. Ordered by the cycle closed, which only moves forward, so a
         * completion dated in the past still counts as the latest when it is.
         */
        fun latestCompletion(view: BinderView, obligation: Obligation): HistoryEntry? =
            view.pointingAt(Tables.history, "obligation", obligation.pk)
                .mapNotNull { view.row(Tables.history, it) }
                .filter { it.isCompletion }
                .maxWithOrNull(byCycleClosed)

        /** Newest first; at the same moment, the later cycle first. */
        private val newestFirst: Comparator<HistoryEntry> =
            compareByDescending<HistoryEntry> { it.occurredAt }
                .thenByDescending { it.cycleDueDay ?: CalendarDay.EARLIEST }

        /** By the cycle closed, then by when. */
        private val byCycleClosed: Comparator<HistoryEntry> =
            compareBy<HistoryEntry> { it.cycleDueDay ?: CalendarDay.EARLIEST }.thenBy { it.occurredAt }
    }
}

/** Whether this record is the completion of a deadline. */
val HistoryEntry.isCompletion: Boolean get() = cycleDueDayISO != null

/** The due day of the cycle it closed. */
val HistoryEntry.cycleDueDay: CalendarDay? get() = StoredDay.day(cycleDueDayISO)

/** The due day its deadline moved to. */
val HistoryEntry.nextDueDay: CalendarDay? get() = StoredDay.day(nextDueDayISO)

/**
 * What deleting a record from Istoric does, worked out once, as the iOS app's `HistoryDeletion`
 * (ios/DosarCuSina/Services/History/HistoryDeletion.swift): the confirmation says it, and
 * [HistoryActions.delete] does exactly it.
 *
 * - Its line items go, and so does the reading it recorded; the value on the section follows the
 *   readings left.
 * - The documents filed with it stay in the binder, under the same section.
 * - A completion moves its deadline back to the cycle it closed only when it is the latest one: deleting
 *   it is as if the deadline wasn't done. An older completion leaves the deadline where it is.
 */
data class HistoryDeletion(
    /** The due day the deadline goes back to, when this is its latest completion. */
    val reopensCycle: CalendarDay?,
    /** The deadline that stays as it is, when this is an older completion. */
    val keepsDeadline: Boolean,
    /** The reading that goes with the record. */
    val removedReading: Double?,
    /** Documents filed with the record, which stay. */
    val keptDocuments: Int,
) {
    companion object {
        fun of(view: BinderView, entry: HistoryEntry): HistoryDeletion {
            val owner = entry.obligation?.let { view.row(Tables.obligations, it) }
            val isLatest = entry.isCompletion && owner != null &&
                HistoryActions.latestCompletion(view, owner)?.pk == entry.pk
            val recorded = entry.metricReading?.takeIf {
                entry.asset != null && HouseholdReadings.readings(view, entry.asset).any { log ->
                    HouseholdReadings.isReading(log, entry)
                }
            }
            return HistoryDeletion(
                reopensCycle = if (isLatest) entry.cycleDueDay else null,
                keepsDeadline = entry.isCompletion && owner != null && !isLatest,
                removedReading = recorded,
                keptDocuments = view.pointingAt(Tables.attachments, "historyEntry", entry.pk).size,
            )
        }
    }
}
