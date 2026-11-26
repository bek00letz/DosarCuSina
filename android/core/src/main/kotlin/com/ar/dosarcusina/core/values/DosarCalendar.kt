package com.ar.dosarcusina.core.values

import java.time.Clock
import java.time.DayOfWeek
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.WeekFields
import java.util.Locale

/**
 * The one calendar the app counts days in, the way [DosarLocale] is the one locale it writes in:
 * Gregorian, in Romanian (weeks start on Monday), in the phone's time zone, as the iOS app's
 * `Calendar.dosar` (ios/Shared/DosarCalendar.swift).
 *
 * Documents, deadlines, Romanian law and the archive's ISO days are all Gregorian, so it is
 * java.time's ISO calendar, whatever calendar or region the phone is set to. The time zone is
 * read each time ([zone]), so a phone that moves to another time zone counts its days there.
 * Every "today" and every day made from a moment goes through here; nothing else asks the
 * platform for its default calendar, time zone or locale.
 *
 * java.time counts Gregorian years before 1583 too, where Foundation's Gregorian calendar
 * counts Julian ones; no record holds such a day.
 */
object DosarCalendar {
    /** Weeks start on Monday. */
    val firstDayOfWeek: DayOfWeek = DayOfWeek.MONDAY

    /** How many days of a year the week it starts in must have to be its first week, as Romanian counts. */
    const val MINIMUM_DAYS_IN_FIRST_WEEK: Int = 1

    /** The weeks of the app's calendar. */
    val weekFields: WeekFields = WeekFields.of(firstDayOfWeek, MINIMUM_DAYS_IN_FIRST_WEEK)

    /** The phone's time zone now: read each time, never kept. The one place it is read. */
    fun zone(): ZoneId = ZoneId.systemDefault()

    /** The day [instant] falls on in [zone]. */
    fun day(instant: Instant, zone: ZoneId = DosarCalendar.zone()): CalendarDay =
        CalendarDay.of(instant, zone)

    /** Today where the phone is, by [clock]. */
    fun today(clock: Clock = Clock.systemUTC(), zone: ZoneId = DosarCalendar.zone()): CalendarDay =
        day(clock.instant(), zone)

    /** The day of the week [day] is (its month's last day for one past it). */
    fun dayOfWeek(day: CalendarDay): DayOfWeek = day.onCalendar.localDate().dayOfWeek

    /** The week of the year [day] is in, by the app's weeks. */
    fun weekOfYear(day: CalendarDay): Int = day.onCalendar.localDate().get(weekFields.weekOfWeekBasedYear())

    /** The year [day]'s week belongs to: the next one for a December week that is the next year's first. */
    fun yearForWeekOfYear(day: CalendarDay): Int = day.onCalendar.localDate().get(weekFields.weekBasedYear())
}

/** The one locale the app writes numbers, dates and money in, whatever the phone's region: Romanian. */
object DosarLocale {
    val locale: Locale = Locale.forLanguageTag("ro-RO")
}
