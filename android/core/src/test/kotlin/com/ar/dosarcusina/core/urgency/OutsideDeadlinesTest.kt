package com.ar.dosarcusina.core.urgency

import com.ar.dosarcusina.core.reminders.BadgePlanner
import com.ar.dosarcusina.core.reminders.ReminderPlanner
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.ObligationStatus
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

/**
 * Examples show inside the app and nowhere outside it, as the iOS app's
 * `ObligationSnapshot.fetchForOutside`: what the reminders, the badge and the widgets are given
 * leaves them out ([DeadlineSnapshot.forOutside]), while Urmează's count still shows what they do.
 */
class OutsideDeadlinesTest {
    private val zone = ZoneId.of("Europe/Bucharest")
    private val now = Instant.parse("2026-11-26T10:00:00Z")
    private val today = CalendarDay.of(now, zone)

    private fun deadline(isExample: Boolean, dueInDays: Int) = DeadlineSnapshot(
        id = UUID.randomUUID(),
        status = ObligationStatus.ACTIVE,
        dueDay = today.addingDays(dueInDays),
        reminders = ReminderProfile(listOf(7, 0), Consequence.LEGAL),
        isExample = isExample,
    )

    private val examples = listOf(deadline(isExample = true, dueInDays = 0), deadline(isExample = true, dueInDays = 3))
    private val own = deadline(isExample = false, dueInDays = 0)

    @Test
    fun `examples never leave the app`() {
        assertEquals(listOf(own), DeadlineSnapshot.forOutside(examples + own))
        assertTrue(DeadlineSnapshot.forOutside(examples).isEmpty())
    }

    @Test
    fun `a binder of examples reminds of nothing and keeps the badge clear`() {
        val outside = DeadlineSnapshot.forOutside(examples)
        assertTrue(ReminderPlanner.plan(examples, now, zone).isEmpty(), "The planner skips an example itself")
        assertTrue(BadgePlanner.plan(emptyList(), outside, now, zone).isEmpty())
        assertEquals(0, BadgePlanner.count(outside, today))
        assertEquals(1, NeedsAction.count(examples, today), "Inside the app they show what Urmează does")
    }
}
