package com.ar.dosarcusina.core.values

import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/**
 * A calendar day with no time or time zone, such as an expiry date or a due date, as the iOS
 * app's `CalendarDay` (ios/Shared/CalendarDay.swift).
 *
 * Written as `yyyy-MM-dd` so the same day means the same thing on every device and platform,
 * whatever the time zone. Its numbers are Gregorian, and so is its arithmetic. A day read from
 * outside keeps its numbers as written, even one the calendar doesn't have ("2026-02-30", or
 * "2567-02-29" from an older build on a phone set to the Buddhist calendar): [isOnCalendar]
 * says so, and every count treats it as its month's last day ([onCalendar]), never as a day of
 * the next month.
 */
data class CalendarDay(val year: Int, val month: Int, val day: Int) : Comparable<CalendarDay> {
    /** Its ISO text: `2026-11-25`, the numbers as they are. */
    val isoString: String get() = MachineText.isoDay(year, month, day)

    override fun toString(): String = isoString

    /** Whether the calendar has this day: false for one kept as written that it doesn't have. */
    val isOnCalendar: Boolean get() = valid(year, month, day) != null

    /** The day the calendar has for these numbers: this one, or its month's last day for one past it. */
    val onCalendar: CalendarDay
        get() {
            // Every month has its first 28 days; only a later one needs its month's length.
            if (month !in 1..MONTHS || day in 1..SHORTEST_MONTH) return this
            return copy(day = day.coerceIn(1, daysInMonth()))
        }

    /** How many days this day's month has: 28 or 29 for February, 30 or 31 for the others. */
    fun daysInMonth(): Int = normalized(year, month, 1).lengthOfMonth()

    /**
     * The same day [months] calendar months away (a year is twelve), or that month's last day
     * when it is shorter: 31 January and one month is 28 or 29 February.
     *
     * The one month arithmetic of the app: every deadline that repeats, every reminder lead in
     * months, every length a document prints. [dayOfMonth] is the day a series keeps (31 for
     * "the 31st") instead of this day's own, so a series moved to 28 February comes back to
     * 31 March; with no months to add, it moves the day within its own month.
     */
    fun addingMonths(months: Int, dayOfMonth: Int? = null): CalendarDay {
        val target = normalized(year, month, 1).plusMonths(months.toLong())
        val wanted = dayOfMonth ?: day
        return CalendarDay(target.year, target.monthValue, wanted.coerceIn(1, target.lengthOfMonth()))
    }

    /** The day [days] days away. */
    fun addingDays(days: Int): CalendarDay = of(localDate().plusDays(days.toLong()))

    /** Whole days from this day to [other], negative when [other] is earlier. */
    fun daysTo(other: CalendarDay): Int = ChronoUnit.DAYS.between(localDate(), other.localDate()).toInt()

    /** Midnight at the start of this day in [zone]: the first moment of it, after a gap the clocks skip. */
    fun startOfDay(zone: ZoneId): Instant = moment(0, zone)

    /**
     * Noon on this day in [zone], twelve hours after it starts, as the iOS app's `CalendarDay.noonDate(in:)`: the
     * moment a day stands for where a record keeps a moment (a document's reading, a deadline in search).
     */
    fun noon(zone: ZoneId): Instant = startOfDay(zone).plus(HALF_A_DAY)

    /**
     * The moment [minuteOfDay] minutes after midnight on this day in [zone], by the clock on the
     * wall. The one place a day becomes a moment.
     *
     * A time the clocks skip that day (03:30 on the morning summer time starts in Romania) is
     * the first minute after the gap, 04:00; a time the clocks show twice (when summer time
     * ends) is the first of the two.
     */
    fun moment(minuteOfDay: Int, zone: ZoneId): Instant {
        val wall = localDate().atStartOfDay().plusMinutes(minuteOfDay.toLong())
        val rules = zone.rules
        if (rules.getValidOffsets(wall).isEmpty()) return rules.getTransition(wall).instant
        return wall.atZone(zone).toInstant()
    }

    /** The java.time date for this day: the day on the calendar, its numbers rolled over for a month past 12. */
    internal fun localDate(): LocalDate = onCalendar.let { normalized(it.year, it.month, it.day) }

    override fun compareTo(other: CalendarDay): Int =
        compareValuesBy(this, other, { it.year }, { it.month }, { it.day })

    companion object {
        private const val MONTHS = 12
        private val HALF_A_DAY: Duration = Duration.ofHours(12)
        private const val SHORTEST_MONTH = 28
        private const val LONGEST_MONTH = 31
        private const val ISO_LENGTH = 10

        /** A year, a month and a day. */
        private const val PARTS = 3

        /** Before every day a record can hold: what a missing day sorts as. */
        val EARLIEST: CalendarDay = CalendarDay(0, 1, 1)

        /**
         * The day with these numbers, or null when the calendar has no such day: 31 February,
         * month 13, day 0. For numbers read from outside (a page, an answer).
         */
        fun valid(year: Int, month: Int, day: Int): CalendarDay? {
            if (month !in 1..MONTHS || day < 1) return null
            if (day > normalized(year, month, 1).lengthOfMonth()) return null
            return CalendarDay(year, month, day)
        }

        /**
         * Reads `yyyy-MM-dd`, and the date part of a full ISO 8601 timestamp. The numbers are
         * kept as written, even for a day the calendar doesn't have; null when it isn't a day.
         * As the iOS reader: the first ten characters, split at each `-`, each piece a number.
         */
        fun parse(text: String): CalendarDay? {
            val pieces = TextRules.pieces(TextRules.prefix(text, ISO_LENGTH), "-")
            val numbers = pieces.mapNotNull(TextRules::swiftInt)
            if (pieces.size != PARTS || numbers.size != PARTS) return null
            val (year, month, day) = numbers
            val fits = year in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong()
            val readable = month in 1L..MONTHS && day in 1L..LONGEST_MONTH && fits
            return if (readable) CalendarDay(year.toInt(), month.toInt(), day.toInt()) else null
        }

        /** The day of a java.time date. */
        fun of(date: LocalDate): CalendarDay = CalendarDay(date.year, date.monthValue, date.dayOfMonth)

        /** The day that contains [instant] in [zone]. */
        fun of(instant: Instant, zone: ZoneId): CalendarDay = of(instant.atZone(zone).toLocalDate())

        /** These numbers as a date, rolled over as a calendar does for a month or day out of range. */
        private fun normalized(year: Int, month: Int, day: Int): LocalDate =
            LocalDate.of(year, 1, 1).plusMonths(month - 1L).plusDays(day - 1L)
    }
}

/**
 * A month and day that repeats every year, such as 31 March for local taxes: `MM-dd`, as the
 * iOS app's `MonthDay`.
 */
data class MonthDay(val month: Int, val day: Int) : Comparable<MonthDay> {
    val isoString: String get() = MachineText.isoMonthDay(month, day)

    override fun toString(): String = isoString

    /** This month-day in [year], clamped to the month's last day (29 February is 28 in common years). */
    fun day(year: Int): CalendarDay = CalendarDay(year, month, 1).addingMonths(0, dayOfMonth = day)

    override fun compareTo(other: MonthDay): Int = compareValuesBy(this, other, { it.month }, { it.day })

    companion object {
        private const val MONTHS = 12L
        private const val LONGEST_MONTH = 31L

        /** Reads `MM-dd`; null when it isn't one. */
        fun parse(text: String): MonthDay? {
            val pieces = TextRules.pieces(text, "-")
            if (pieces.size != 2) return null
            val month = TextRules.swiftInt(pieces[0]) ?: return null
            val day = TextRules.swiftInt(pieces[1]) ?: return null
            if (month !in 1L..MONTHS || day !in 1L..LONGEST_MONTH) return null
            return MonthDay(month.toInt(), day.toInt())
        }
    }
}

/**
 * How the database keeps a day: as its ISO text, `2026-11-15`, written by [MachineText] like the
 * archive's days, as the iOS app's `StoredDay`. The text is the same day everywhere, and it sorts
 * as the days do.
 */
object StoredDay {
    private const val ISO_LENGTH = 10

    /** The stored text of [day]. */
    fun text(day: CalendarDay): String = day.isoString

    /** The day [text] holds; null when there is none or it isn't a day of ten characters. */
    fun day(text: String?): CalendarDay? {
        if (text == null || TextRules.characters(text).size != ISO_LENGTH) return null
        return CalendarDay.parse(text)
    }
}
