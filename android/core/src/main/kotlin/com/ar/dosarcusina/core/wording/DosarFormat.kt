package com.ar.dosarcusina.core.wording

import com.ar.dosarcusina.core.reminders.ReminderClock
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.DosarCalendar
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId

/** How a date is written: the shapes of the iOS app's `DosarFormat`. */
enum class DateStyle {
    /** „14 mar. 2025” */
    DAY,

    /** „14 martie 2025” */
    LONG_DAY,

    /** „14 martie” */
    DAY_MONTH,

    /** „martie 2025” */
    MONTH_YEAR,

    /** „14.03.2025”, as printed on Romanian documents. */
    NUMERIC_DAY,
}

/**
 * Dates the way the app writes them, in Romanian whatever the phone's language, as the iOS app's
 * `DosarFormat` (ios/Shared/DosarFormat.swift). Every screen, widget, notification and search
 * entry writes dates here.
 *
 * A [CalendarDay] (a due day, an expiry) has no time and no time zone: it is written as the day
 * it is, with its own numbers, even one the calendar doesn't have („30 februarie 2026”). A moment
 * ([Instant]) is written as the day it falls on in a time zone, the phone's unless the caller
 * counts days in another. The month names are Romanian's, as Foundation writes them ([RomanianMonths]),
 * never the machine's locale data.
 */
object DosarFormat {
    private const val MINUTES_IN_HOUR = 60
    private const val CENTURY = 100

    /** „14 mar. 2025” */
    fun day(day: CalendarDay): String = write(day, DateStyle.DAY)

    /** „14 martie 2025” */
    fun longDay(day: CalendarDay): String = write(day, DateStyle.LONG_DAY)

    /** „14 martie” */
    fun dayMonth(day: CalendarDay): String = write(day, DateStyle.DAY_MONTH)

    /** „martie 2025” */
    fun monthYear(day: CalendarDay): String = write(day, DateStyle.MONTH_YEAR)

    /** [day] in [style]: a day past its month's end keeps its own number; a month past 12 goes on to the next year. */
    fun write(day: CalendarDay, style: DateStyle): String {
        val shown = if (day.month in 1..RomanianMonths.COUNT) day else CalendarDay.of(day.localDate())
        return write(shown.year, shown.month, shown.day, style)
    }

    /** The day [moment] falls on in [zone], in [style]. */
    fun write(moment: Instant, style: DateStyle, zone: ZoneId = DosarCalendar.zone()): String {
        val wall = LocalDateTime.ofInstant(moment, zone)
        return write(wall.year, wall.monthValue, wall.dayOfMonth, style)
    }

    /** „08/28”: the month a bank card is valid through, as cards print it. */
    fun cardExpiry(day: CalendarDay): String {
        val shown = CalendarDay.of(day.localDate())
        return twoDigits(shown.month) + "/" + twoDigits(Math.floorMod(shown.year, CENTURY))
    }

    /** „14:05”: the time [moment] shows in [zone]. */
    fun time(moment: Instant, zone: ZoneId = DosarCalendar.zone()): String {
        val wall = LocalDateTime.ofInstant(moment, zone)
        return twoDigits(wall.hour) + ":" + twoDigits(wall.minute)
    }

    /** „09:00”: a time of day kept as minutes after midnight (a reminder's time), held to the day. */
    fun time(minuteOfDay: Int): String {
        val minute = ReminderClock.clamped(minuteOfDay)
        return twoDigits(minute / MINUTES_IN_HOUR) + ":" + twoDigits(minute % MINUTES_IN_HOUR)
    }

    private fun write(year: Int, month: Int, day: Int, style: DateStyle): String = when (style) {
        DateStyle.DAY -> "$day ${RomanianMonths.abbreviated(month)} $year"
        DateStyle.LONG_DAY -> "$day ${RomanianMonths.wide(month)} $year"
        DateStyle.DAY_MONTH -> "$day ${RomanianMonths.wide(month)}"
        DateStyle.MONTH_YEAR -> "${RomanianMonths.wide(month)} $year"
        DateStyle.NUMERIC_DAY -> "${twoDigits(day)}.${twoDigits(month)}.$year"
    }

    private fun twoDigits(number: Int): String = number.toString().padStart(2, '0')
}

/**
 * Romanian's month names as Foundation writes them in the app's locale (ro_RO), pinned by the iOS
 * app's answers in shared/test-vectors/wording/: wide („martie”) and abbreviated („mar.”).
 */
object RomanianMonths {
    const val COUNT: Int = 12

    private val WIDE = listOf(
        "ianuarie", "februarie", "martie", "aprilie", "mai", "iunie",
        "iulie", "august", "septembrie", "octombrie", "noiembrie", "decembrie",
    )
    private val ABBREVIATED = listOf(
        "ian.", "feb.", "mar.", "apr.", "mai", "iun.", "iul.", "aug.", "sept.", "oct.", "nov.", "dec.",
    )

    /** „martie” for 3. */
    fun wide(month: Int): String = WIDE[month - 1]

    /** „mar.” for 3. */
    fun abbreviated(month: Int): String = ABBREVIATED[month - 1]
}
