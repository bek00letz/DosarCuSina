package com.ar.dosarcusina.store.obligations

import com.ar.dosarcusina.archive.v3.RecurrenceRule
import com.ar.dosarcusina.core.values.ObligationStatus
import com.ar.dosarcusina.core.values.ThreeWay
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.UndoReceipt
import com.ar.dosarcusina.store.UnitOfWork
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.keptRecurrence
import com.ar.dosarcusina.store.schema.withKeptRecurrence
import java.time.Instant

/** Where the deadline stands, as stored. */
val Obligation.status: ObligationStatus get() = ObligationStatus.stored(statusRaw)

/**
 * The one way a deadline changes, as the iOS app's `ObligationActions`
 * (ios/DosarCuSina/Services/Obligations/ObligationActions.swift): each its own undoable step, saved
 * once through the unit of work, which joins a step it runs inside (a category's edit pausing its
 * service deadlines). This is its start, what a category's edit needs: [pause], [resume] and
 * [setRecurrence]; completing, snoozing, rescheduling and the rest come with Phase 3 and extend
 * this class, never a second one.
 */
class ObligationActions(
    private val unit: UnitOfWork,
    /** The step's clock: the change time it gives. */
    private val now: () -> Instant = unit.clock,
) {
    /** Pauses [obligation]: it stops reminding until it is resumed. Undoable. */
    fun pause(obligation: Obligation): UndoReceipt =
        unit.performUndoable(now()) { step -> setStatus(step, obligation, ObligationStatus.PAUSED) }.receipt

    /** Starts a paused deadline again. Undoable, like [pause]. */
    fun resume(obligation: Obligation): UndoReceipt =
        unit.performUndoable(now()) { step -> setStatus(step, obligation, ObligationStatus.ACTIVE) }.receipt

    /**
     * Changes how [obligation] repeats (a service every 150 hours instead of 100). The due day and
     * the counter it is due at stay; the new rule counts from the next cycle. Undoable.
     *
     * Only what the change made from the rule it started from ([startedFrom], else the one stored
     * now) is written, part by part ([ThreeWay]): an interval changed here and an anchor changed
     * meanwhile both stay.
     */
    fun setRecurrence(obligation: Obligation, rule: RecurrenceRule, startedFrom: RecurrenceRule? = null): UndoReceipt =
        unit.performUndoable(now()) { step ->
            val row = fresh(step, obligation)
            val kept = row.keptRecurrence
            val laid = ThreeWay.laying(rule, kept.value, startedFrom ?: kept.value, RecurrenceRule.codec)
            if (laid != kept.value) step.update(row.withKeptRecurrence(kept.replacingValue(laid)))
        }.receipt

    private fun setStatus(step: Step, obligation: Obligation, status: ObligationStatus) {
        val row = fresh(step, obligation)
        val snoozed = if (status == ObligationStatus.ACTIVE) row.snoozedUntilISO else null
        step.update(row.copy(statusRaw = status.raw, snoozedUntilISO = snoozed))
    }

    private fun fresh(step: Step, obligation: Obligation): Obligation =
        step.row(Tables.obligations, obligation.pk) ?: throw NoSuchElementException("The deadline isn't in the binder")
}
