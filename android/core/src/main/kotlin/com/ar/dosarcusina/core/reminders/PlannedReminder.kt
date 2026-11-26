package com.ar.dosarcusina.core.reminders

import com.ar.dosarcusina.core.values.CalendarDay
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.UUID

/** What a planned reminder is for: the strings word each one, the plan never does. */
enum class ReminderPurpose {
    /** A lead before the due day: `obligation.<id>.d<days>`. */
    LEAD,

    /** A lead before a travel cut-off (a passport): `obligation.<id>.t<days>`. */
    TRAVEL_LEAD,

    /** The one follow-up the day after the due day: `obligation.<id>.lapse`. */
    FOLLOW_UP,

    /** The one catch-up for warnings that passed before the deadline was known: `obligation.<id>.catchup`. */
    CATCH_UP,

    /** The day a snooze ends: `obligation.<id>.snooze`. */
    SNOOZE,

    /** Only sets the badge as a day starts, showing nothing: `obligation.badge.<yyyy-MM-dd>`. */
    BADGE,

    /** „Open the app so reminders continue”, when the phone can't hold every one: `obligation.continue`. */
    CONTINUE,
}

/**
 * The date parts a reminder's moment is handed to the system in, as the iOS app's
 * `ReminderTrigger.components`: year, month, day, hour and minute on the wall clock, in the
 * app's calendar (Gregorian) and the time zone the plan was made in. The parts name a wall-clock
 * time and no zone, so a reminder fires at its hour wherever the phone is; a move to another
 * time zone plans every reminder again anyway.
 */
data class TriggerParts(val year: Int, val month: Int, val day: Int, val hour: Int, val minute: Int) {
    companion object {
        /** The date parts of [moment] in [zone]. */
        fun of(moment: Instant, zone: ZoneId): TriggerParts {
            val wall = LocalDateTime.ofInstant(moment, zone)
            return TriggerParts(wall.year, wall.monthValue, wall.dayOfMonth, wall.hour, wall.minute)
        }
    }
}

/**
 * A reminder the app wants pending, as the iOS app's `PlannedReminder`
 * (ios/DosarCuSina/Services/Reminders/ReminderPlanner.swift), without its words: what it says
 * comes from the strings (Phase 6), from its [purpose], its [day], its deadline and the fire day.
 * Two plans are the same exactly when their reminders are equal.
 */
data class PlannedReminder(
    /** Unique in a plan, under [ReminderPlanner.IDENTIFIER_PREFIX]. */
    val identifier: String,
    val purpose: ReminderPurpose,
    /** The deadline it is about; null for the badge-only and the „open the app” reminders. */
    val obligationId: UUID?,
    /** The due day of the cycle it is about: a button tapped on it acts only while the deadline is still on it. */
    val cycle: CalendarDay?,
    /** The day it is planned for (a lead's day, the day after the due day, the day a snooze ends). */
    val day: CalendarDay?,
    val fireAt: Instant,
    /** The moment's date parts in the app's calendar, as the system gets them. */
    val trigger: TriggerParts,
    /** May break through Do Not Disturb: the last reminders of a deadline whose consequence allows it. */
    val isTimeSensitive: Boolean = false,
    /** Its deadline's category is locked on this device: generic words, and „Am rezolvat” asks for the lock first. */
    val isProtected: Boolean = false,
    /** Closing its deadline asks a new day or a new document: „Am rezolvat” opens the app's „Am rezolvat”. */
    val closesInTheApp: Boolean = false,
    /** The app's badge once it fires, the count of the day it fires on ([BadgePlanner]); null leaves it as it is. */
    val badge: Int? = null,
    /** False for a reminder that only sets the badge: no title, no sound, nothing shown. */
    val showsAlert: Boolean = true,
)
