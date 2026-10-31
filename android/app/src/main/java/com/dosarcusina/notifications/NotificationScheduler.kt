package com.dosarcusina.notifications

import com.dosarcusina.data.LifecycleEventEntity
import java.util.Calendar

data class ScheduledAlert(
    val eventId: String,
    val offsetDays: Int,
    val triggerTimestamp: Long,
    val title: String,
    val message: String
)

/**
 * Notification reminder calculation and scheduling engine.
 */
object NotificationScheduler {

    const val RESOLVE_ACTION_ID = "ACTION_RESOLVE"
    const val SNOOZE_3D_ACTION_ID = "ACTION_SNOOZE_3D"

    /**
     * Calculates the scheduled alert timestamps for an event, dropping past timestamps.
     */
    fun calculateScheduledAlerts(
        event: LifecycleEventEntity,
        currentTimestamp: Long = System.currentTimeMillis()
    ): List<ScheduledAlert> {
        if (event.isCompleted) return emptyList()

        val results = mutableListOf<ScheduledAlert>()
        val offsets = if (event.reminderOffsetDays.isNotEmpty()) event.reminderOffsetDays else listOf(30, 7, 1, 0)

        for (offset in offsets) {
            val alertCal = Calendar.getInstance().apply {
                timeInMillis = event.dueDate
                add(Calendar.DAY_OF_YEAR, -offset)
                set(Calendar.HOUR_OF_DAY, 9)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }

            val triggerTime = alertCal.timeInMillis
            if (triggerTime > currentTimestamp) {
                val message = when (offset) {
                    0 -> "Termenul scade astăzi!"
                    1 -> "Termenul scade mâine!"
                    else -> "Termenul scade peste $offset zile."
                }
                results.add(
                    ScheduledAlert(
                        eventId = event.id,
                        offsetDays = offset,
                        triggerTimestamp = triggerTime,
                        title = event.title,
                        message = message
                    )
                )
            }
        }

        return results.sortedBy { it.triggerTimestamp }
    }

    /**
     * Calculates new due date when snoozing by 3 days.
     */
    fun calculateSnoozeDueDate(
        currentDueDate: Long,
        currentTimestamp: Long = System.currentTimeMillis()
    ): Long {
        val baseDate = if (currentDueDate > currentTimestamp) currentDueDate else currentTimestamp
        val cal = Calendar.getInstance().apply {
            timeInMillis = baseDate
            add(Calendar.DAY_OF_YEAR, 3)
        }
        return cal.timeInMillis
    }
}
