package com.ar.dosarcusina.store.obligations

import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.history.HistoryActions
import com.ar.dosarcusina.store.history.cycleDueDay
import com.ar.dosarcusina.store.history.nextDueDay
import com.ar.dosarcusina.store.schema.Obligation
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

/**
 * Deadlines whose last "done" may have come from an old reminder button, before buttons acted only on
 * the cycle they were about, as the iOS app's `LikelyDoubleCompletions`
 * (ios/DosarCuSina/Intents/LikelyDoubleCompletions.swift): the two latest completions a few days apart,
 * closing consecutive cycles, the second still well ahead. Such a cycle can't be told apart with
 * certainty from one paid early, so [find] changes nothing. The repair list shows each one and runs
 * [undoSecond] only with the person's OK.
 */
object LikelyDoubleCompletions {
    /** The second completion came this soon after the first, in days. */
    const val WITHIN_DAYS: Int = 7

    /** And closed a cycle at least this far ahead of the day it was recorded, in days. */
    const val AHEAD_DAYS: Int = 8

    /** One likely case: the deadline, the completion to offer to delete (the latest), and the cycle it closed. */
    data class Candidate(val obligationId: UUID, val historyEntryId: UUID, val closedCycle: CalendarDay)

    /** A completion as the rule reads it: when it was recorded, the cycle it closed and the day it moved to. */
    data class Completion(val id: UUID, val occurredAt: Instant, val cycle: CalendarDay?, val next: CalendarDay?)

    /** Whether the two latest completions (newest first) look like one real and one stale tap, counted in [zone]. */
    fun isLikely(latest: Completion, previous: Completion, zone: ZoneId): Boolean {
        val closed = latest.cycle ?: return false
        if (previous.next != closed) return false
        val latestDay = CalendarDay.of(latest.occurredAt, zone)
        val apart = CalendarDay.of(previous.occurredAt, zone).daysTo(latestDay)
        return apart in 0..WITHIN_DAYS && latestDay.daysTo(closed) >= AHEAD_DAYS
    }

    /** Every likely case in the binder, in row order. Reads only. */
    fun find(view: BinderView, zone: ZoneId): List<Candidate> =
        view.all(Tables.obligations).mapNotNull { candidate(view, it, zone) }

    /**
     * Deletes the second completion of a case the person confirmed, in [step], as Istoric would: it is the
     * latest, so the deadline goes back to the cycle it closed. Safe to run again: it acts only while that
     * completion is still the latest and still looks like a stale tap, and gives whether it changed anything.
     */
    fun undoSecond(step: Step, candidate: Candidate, zone: ZoneId): Boolean {
        val obligation = step.all(Tables.obligations).firstOrNull { it.id == candidate.obligationId } ?: return false
        if (candidate(step, obligation, zone) != candidate) return false
        val entry = HistoryActions.history(step, obligation).firstOrNull() ?: return false
        if (HistoryActions.latestCompletion(step, obligation)?.pk != entry.pk) return false
        HistoryActions.delete(step, entry)
        return true
    }

    private fun candidate(view: BinderView, obligation: Obligation, zone: ZoneId): Candidate? {
        val history = HistoryActions.history(view, obligation).take(2)
            .map { Completion(it.id, it.occurredAt, it.cycleDueDay, it.nextDueDay) }
        if (history.size != 2 || !isLikely(history[0], history[1], zone)) return null
        val closed = history[0].cycle ?: return null
        return Candidate(obligation.id, history[0].id, closed)
    }
}
