package com.ar.dosarcusina.core.reminders

import com.ar.dosarcusina.core.urgency.DeadlineSnapshot
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.ObligationStatus
import java.util.UUID

/** A reminder shown in the notification shade, as the system gives it back. */
data class DeliveredReminder(
    val identifier: String,
    val obligationId: UUID?,
    /** The cycle it was about. */
    val cycle: CalendarDay?,
    /** It was written with a locked category's generic words; otherwise it names the deadline. */
    val isProtected: Boolean = false,
)

/**
 * Which shown reminders no longer belong in the notification shade, as the pure part of the iOS
 * app's `NotificationReconciler.isOutdated`: each pass clears what a reminder planned now
 * wouldn't say.
 */
object ShownReminders {
    /**
     * [openCycles] holds the due day of every deadline that still reminds (active ones);
     * [locked] the deadlines whose category is locked on this device now.
     */
    fun isOutdated(
        reminder: DeliveredReminder,
        openCycles: Map<UUID, CalendarDay>,
        locked: Set<UUID>,
    ): Boolean {
        if (isClosed(reminder, openCycles)) return true
        val id = reminder.obligationId ?: return false
        return id in locked && !reminder.isProtected
    }

    /**
     * A shown reminder whose cycle is no longer open: its deadline is gone, closed or on another
     * cycle. The badge-only and „open the app” reminders have done their job once the app planned again.
     */
    fun isClosed(reminder: DeliveredReminder, openCycles: Map<UUID, CalendarDay>): Boolean {
        val id = reminder.obligationId ?: return true
        val open = openCycles[id] ?: return true
        return reminder.cycle?.let { it != open } ?: false
    }

    /** The open cycle of every active deadline, which [isOutdated] reads: the first of two copies of one id wins. */
    fun openCycles(deadlines: List<DeadlineSnapshot>): Map<UUID, CalendarDay> {
        val cycles = LinkedHashMap<UUID, CalendarDay>()
        for (deadline in deadlines) {
            if (deadline.status == ObligationStatus.ACTIVE) {
                cycles.putIfAbsent(deadline.id, deadline.dueDay)
            }
        }
        return cycles
    }

    /** The deadlines whose category is locked on this device now, which [isOutdated] reads. */
    fun locked(deadlines: List<DeadlineSnapshot>): Set<UUID> = deadlines.filter { it.isSensitive }.map { it.id }.toSet()
}
