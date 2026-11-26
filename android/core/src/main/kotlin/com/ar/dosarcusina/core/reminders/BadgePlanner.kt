package com.ar.dosarcusina.core.reminders

import com.ar.dosarcusina.core.urgency.DeadlineSnapshot
import com.ar.dosarcusina.core.urgency.NeedsAction
import com.ar.dosarcusina.core.values.CalendarDay
import java.time.Instant
import java.time.ZoneId

/**
 * The app's badge while the app stays closed, as the iOS app's `BadgePlanner`
 * (ios/DosarCuSina/Services/Reminders/BadgePlanner.swift). A pass sets the badge to what needs
 * doing now ([NeedsAction.count]), but the count moves as days pass, and the app may not run on
 * those days. So the badge travels with the reminders:
 *
 * - every reminder carries the badge as it will be on the day it fires;
 * - on each of the next [HORIZON_DAYS] days whose count differs from the day before, a reminder
 *   that shows nothing sets the badge as that day starts, in the room the reminders leave.
 *
 * Each count is worked out as if nothing is done meanwhile; anything the person does saves, and
 * the pass that follows plans them all again. Pure: no notification manager, no clock.
 */
object BadgePlanner {
    /** A reminder that only sets the badge: `obligation.badge.<yyyy-MM-dd>`, under the reminders' prefix. */
    const val IDENTIFIER_PREFIX: String = ReminderPlanner.IDENTIFIER_PREFIX + "badge."

    /** How many days ahead the badge is planned on its own: a week, by which the app has usually run again. */
    const val HORIZON_DAYS: Int = 7

    /** The badge on [day], by the app's one count. */
    fun count(deadlines: List<DeadlineSnapshot>, day: CalendarDay): Int = NeedsAction.count(deadlines, day)

    /**
     * [reminders], each with the badge of the day it fires in [zone], then the badge-only
     * reminders for the next days whose count changes, as many as fit under [limit].
     */
    fun plan(
        reminders: List<PlannedReminder>,
        deadlines: List<DeadlineSnapshot>,
        now: Instant,
        zone: ZoneId,
        limit: Int = ReminderPlanner.DEFAULT_LIMIT,
    ): List<PlannedReminder> {
        val counts = HashMap<CalendarDay, Int>()
        fun badge(day: CalendarDay): Int = counts.getOrPut(day) { count(deadlines, day) }

        val planned = reminders.map { it.copy(badge = badge(CalendarDay.of(it.fireAt, zone))) }.toMutableList()
        val today = CalendarDay.of(now, zone)
        var room = limit - planned.size
        var previous = badge(today)
        for (offset in 1..HORIZON_DAYS) {
            if (room <= 0) break
            val day = today.addingDays(offset)
            val value = badge(day)
            if (value != previous) {
                planned += badgeOnly(value, day, zone)
                room -= 1
            }
            previous = value
        }
        return planned
    }

    /** The reminder that only sets the badge to [count] as [day] starts in [zone]. */
    internal fun badgeOnly(count: Int, day: CalendarDay, zone: ZoneId): PlannedReminder {
        val fire = day.startOfDay(zone)
        return PlannedReminder(
            identifier = IDENTIFIER_PREFIX + day.isoString,
            purpose = ReminderPurpose.BADGE,
            obligationId = null,
            cycle = null,
            day = day,
            fireAt = fire,
            trigger = TriggerParts.of(fire, zone),
            badge = count,
            showsAlert = false,
        )
    }
}
