package com.ar.dosarcusina.store

import com.ar.dosarcusina.store.schema.Obligation
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import java.math.BigDecimal

/**
 * Since when a deadline's cycle is known as it now is ([Obligation.cycleKnownAt], kept by
 * [CycleTimes]): it moves when the due day, the reminders' leads, the travel margin or whether the
 * deadline is active change, whoever changes them, and never for anything else. Its change time is
 * another thing: the app's own steps leave that alone (the iOS app's `CycleKnownSinceTests`).
 */
class CycleTimesTest {
    private val made = noon("2026-12-01")
    private val later = noon("2026-12-10")
    private val binder = TestBinderStore()
    private val unit = binder.unit

    /** A passport's renewal made at [made] by the person: reminders 90 days before it expires and on the day. */
    private fun passport(): Obligation = unit.perform(now = made) { step ->
        step.insert(Obligation(
            title = "Pașaport",
            kindRaw = "renewal",
            dueDayISO = "2027-08-12",
            reminderLeadDays = listOf(90, 0),
        ))
    }

    private fun stored(record: Obligation) = binder.stored(record)

    @Test
    fun aDeadlineIsKnownFromWhenItIsMade() {
        assertEquals(made, stored(passport()).cycleKnownAt)
    }

    @Test
    fun theAppsOwnStepThatMovesTheLeadsIsAFreshAnchor() {
        val renewal = passport()
        // What the travel cut-off's repair does, as the app's own step.
        unit.perform(ChangeOrigin.APP, now = later) { step ->
            step.update(stored(renewal).copy(travelMarginDays = 180))
        }
        assertEquals(made, stored(renewal).updatedAt, "The app's step gives no change time")
        assertEquals(later, stored(renewal).cycleKnownAt, "It is known with these reminders from now")
    }

    @Test
    fun aRescheduleIsAFreshAnchorAndUndoPutsTheOldOneBack() {
        val renewal = passport()
        val receipt = unit.performUndoable(now = later) { step ->
            step.update(stored(renewal).copy(dueDayISO = "2027-09-01"))
        }.receipt
        assertEquals(later, stored(renewal).cycleKnownAt)
        assertEquals(later, stored(renewal).updatedAt)
        receipt.undo()
        assertEquals(made, stored(renewal).cycleKnownAt)
        assertEquals("2027-08-12", stored(renewal).dueDayISO)
    }

    @Test
    fun aNewerCycleTimeStaysThroughUndo() {
        val renewal = passport()
        val receipt = unit.performUndoable(now = later) { step ->
            step.update(stored(renewal).copy(dueDayISO = "2027-09-01"))
        }.receipt
        val repaired = noon("2026-12-15")
        unit.perform(ChangeOrigin.APP, now = repaired) { step ->
            step.update(stored(renewal).copy(travelMarginDays = 180))
        }
        assertEquals(repaired, stored(renewal).cycleKnownAt)
        receipt.undo()
        assertEquals("2027-08-12", stored(renewal).dueDayISO, "The person's step is taken back")
        assertEquals(180, stored(renewal).travelMarginDays, "The repair since stays")
        assertEquals(repaired, stored(renewal).cycleKnownAt, "Known with these reminders since the repair")
    }

    @Test
    fun theirRemindersAndResumingAreAFreshAnchor() {
        val renewal = passport()
        unit.perform(now = later) { step -> step.update(stored(renewal).copy(reminderLeadDays = listOf(30, 0))) }
        assertEquals(later, stored(renewal).cycleKnownAt)
        val paused = noon("2026-12-20")
        val resumed = noon("2027-01-15")
        unit.perform(now = paused) { step -> step.update(stored(renewal).copy(statusRaw = "paused")) }
        assertEquals(paused, stored(renewal).cycleKnownAt, "Stopped: nothing reminds")
        unit.perform(now = resumed) { step -> step.update(stored(renewal).copy(statusRaw = "active")) }
        assertEquals(
            resumed,
            stored(renewal).cycleKnownAt,
            "Started again: what passed while it was stopped is made up for",
        )
    }

    @Test
    fun aSnoozeKeepsTheAnchor() {
        val renewal = passport()
        unit.perform(now = later) { step -> step.update(stored(renewal).copy(snoozedUntilISO = "2026-12-11")) }
        assertEquals(later, stored(renewal).updatedAt, "It is the person's change")
        assertEquals(made, stored(renewal).cycleKnownAt)
    }

    @Test
    fun anUnrelatedEditKeepsTheAnchor() {
        val renewal = passport()
        unit.perform(now = later) { step ->
            step.update(
                stored(renewal).copy(
                    notes = "Programare la ghișeu.",
                    estimatedCostAmount = BigDecimal("40"),
                    estimatedCostCurrency = "RON",
                    reminderMinuteOfDay = 20 * 60,
                ),
            )
        }
        assertEquals(later, stored(renewal).updatedAt)
        assertEquals(made, stored(renewal).cycleKnownAt)
    }

    @Test
    fun aBackupsCopyKeepsTheMomentItCarries() {
        val carried = noon("2026-06-01")
        val copy = unit.performPrivate { step ->
            step.insert(Obligation(title = "ITP", dueDayISO = "2027-03-01", cycleKnownAt = carried))
        }
        assertEquals(carried, stored(copy).cycleKnownAt)
    }
}
