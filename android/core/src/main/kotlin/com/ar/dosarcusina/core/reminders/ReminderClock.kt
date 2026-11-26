package com.ar.dosarcusina.core.reminders

import com.ar.dosarcusina.core.values.CalendarDay
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * A time of day kept as minutes after midnight (the general reminder time in Settings, a
 * deadline's own „Ora amintirii”), as the iOS app's `ReminderClock` (ios/Shared/ReminderClock.swift).
 * A day and a time become a moment only through [CalendarDay.moment], which puts a time the
 * clocks skip at the first minute after the gap.
 */
object ReminderClock {
    private const val MINUTES_IN_HOUR = 60
    private const val LAST_MINUTE = 24 * MINUTES_IN_HOUR - 1

    /** A time zone moves its clocks at most a few times a year. */
    private const val CHANGES_IN_A_YEAR = 4

    /** The general reminder time when the person hasn't chosen one: 9:00. */
    const val DEFAULT_MINUTE_OF_DAY: Int = 9 * MINUTES_IN_HOUR

    /** 0:00 to 23:59. */
    fun clamped(minuteOfDay: Int): Int = minuteOfDay.coerceIn(0, LAST_MINUTE)

    /** The moment of [minuteOfDay] on [day] in [zone], within the day: never a minute of the next one. */
    fun moment(day: CalendarDay, minuteOfDay: Int, zone: ZoneId): Instant = day.moment(clamped(minuteOfDay), zone)

    /** The minutes after midnight the clock on the wall shows at [moment] in [zone]. */
    fun minuteOfDay(moment: Instant, zone: ZoneId): Int {
        val wall = LocalDateTime.ofInstant(moment, zone)
        return clamped(wall.hour * MINUTES_IN_HOUR + wall.minute)
    }

    /** The day within a year when the clocks skip a reminder's time, and the time it comes at that day. */
    data class SkippedTime(val day: CalendarDay, val remindsAt: Int)

    /**
     * The next day within a year after [now] when the clocks skip [minuteOfDay] (the morning
     * summer time starts: 03:30 doesn't exist in Romania when 03:00 becomes 04:00), with the time
     * a reminder set for it comes at that day, the first minute after the gap. Null when the
     * time exists every day of the next year in [zone]. Its page says it.
     */
    fun springForward(minuteOfDay: Int, now: Instant, zone: ZoneId): SkippedTime? {
        val minute = clamped(minuteOfDay)
        val yearOn = ZonedDateTime.ofInstant(now, zone).plusYears(1).toInstant()
        return generateSequence(zone.rules.nextTransition(now)) { zone.rules.nextTransition(it.instant) }
            .take(CHANGES_IN_A_YEAR)
            .map { it.instant }
            .takeWhile { !it.isAfter(yearOn) }
            .firstNotNullOfOrNull { change -> skipped(minute, change, zone) }
    }

    /** The day of [change] when the clocks skip [minute] that day, with the time it comes at instead. */
    private fun skipped(minute: Int, change: Instant, zone: ZoneId): SkippedTime? {
        val day = CalendarDay.of(change, zone)
        val moment = day.moment(minute, zone)
        val shown = minuteOfDay(moment, zone)
        return if (shown != minute && CalendarDay.of(moment, zone) == day) SkippedTime(day, shown) else null
    }
}
