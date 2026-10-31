package com.dosarcusina.notifications

import com.dosarcusina.data.LifecycleEventEntity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar

class NotificationSchedulerTest {

    @Test
    fun testScheduleRemindersFarFutureEvent() {
        val now = 1700000000000L // arbitrary fixed timestamp
        // Due in 45 days
        val dueDate = now + (45L * 86_400_000L)

        val event = LifecycleEventEntity(
            assetId = "test-asset",
            title = "RCA Asigurare",
            dueDate = dueDate,
            reminderOffsetDays = listOf(30, 7, 1, 0)
        )

        val alerts = NotificationScheduler.calculateScheduledAlerts(event, currentTimestamp = now)
        // All 4 alerts should be scheduled
        assertEquals(4, alerts.size)
        assertEquals(listOf(30, 7, 1, 0), alerts.map { it.offsetDays }.sortedDescending())
    }

    @Test
    fun testScheduleRemindersDropsPastOffsets() {
        val now = 1700000000000L
        // Due in 5 days
        val dueDate = now + (5L * 86_400_000L)

        val event = LifecycleEventEntity(
            assetId = "test-asset",
            title = "Rovinieta",
            dueDate = dueDate,
            reminderOffsetDays = listOf(30, 7, 1, 0)
        )

        val alerts = NotificationScheduler.calculateScheduledAlerts(event, currentTimestamp = now)
        // 30 days and 7 days are in the past relative to now, so only 1 day and 0 day remain
        assertEquals(2, alerts.size)
        assertEquals(listOf(1, 0), alerts.map { it.offsetDays }.sortedDescending())
    }

    @Test
    fun testCompletedEventReturnsZeroAlerts() {
        val now = 1700000000000L
        val dueDate = now + (45L * 86_400_000L)

        val event = LifecycleEventEntity(
            assetId = "test-asset",
            title = "ITP Rezolvat",
            dueDate = dueDate,
            isCompleted = true,
            reminderOffsetDays = listOf(30, 7, 1, 0)
        )

        val alerts = NotificationScheduler.calculateScheduledAlerts(event, currentTimestamp = now)
        assertTrue(alerts.isEmpty())
    }

    @Test
    fun testSnoozeRecalculation() {
        val now = 1700000000000L
        val currentDue = now + 86_400_000L // due tomorrow
        val newDue = NotificationScheduler.calculateSnoozeDueDate(currentDue, currentTimestamp = now)

        val expected = currentDue + (3L * 86_400_000L)
        assertEquals(expected, newDue)
    }
}
