package com.ar.dosarcusina.core.values

/**
 * A calendar step, as the iOS app's `RecurrenceInterval` (ios/DosarCuSina/Models/Obligations/ObligationTypes.swift):
 * [every] units of time, from one to a hundred years' worth ([longest]), however it is made: in the app, from a
 * backup, from another device. Made through [of], which keeps [every] within that range.
 */
class RecurrenceInterval private constructor(val every: Int, val unit: Unit) {
    enum class Unit(val raw: String) {
        DAY("day"),
        WEEK("week"),
        MONTH("month"),
        YEAR("year"),
        ;

        companion object {
            /** The unit stored as [raw]; null for one this build doesn't know. */
            fun stored(raw: String): Unit? = entries.firstOrNull { it.raw == raw }
        }
    }

    /**
     * [day] moved by this interval, as the iOS app's `RecurrenceEngine.add`: days and weeks by days, months and
     * years by the one month arithmetic ([CalendarDay.addingMonths]: the same day, or the month's last day when it
     * is shorter, and with [dayOfMonth] the day a series keeps).
     */
    fun after(day: CalendarDay, dayOfMonth: Int? = null): CalendarDay = when (unit) {
        Unit.DAY -> day.addingDays(every)
        Unit.WEEK -> day.addingDays(every * DAYS_IN_A_WEEK)
        Unit.MONTH -> day.addingMonths(every, dayOfMonth)
        Unit.YEAR -> day.addingMonths(every * MONTHS_IN_A_YEAR, dayOfMonth)
    }

    /** [times] of this interval, as one: within the same range. */
    fun times(times: Int): RecurrenceInterval = of(every * times, unit)

    override fun equals(other: Any?): Boolean =
        other is RecurrenceInterval && other.every == every && other.unit == unit

    override fun hashCode(): Int = 31 * every + unit.hashCode()

    override fun toString(): String = "$every ${unit.raw}"

    companion object {
        private const val DAYS_IN_A_WEEK = 7
        private const val MONTHS_IN_A_YEAR = 12
        private const val LONGEST_DAYS = 36_500
        private const val LONGEST_WEEKS = 5_200
        private const val LONGEST_MONTHS = 1_200
        private const val LONGEST_YEARS = 100

        /**
         * The most of a unit an interval can be: a hundred years, in that unit. Nothing that repeats in a household
         * waits longer, and every day worked out from it stays a day the calendar has.
         */
        fun longest(unit: Unit): Int = when (unit) {
            Unit.DAY -> LONGEST_DAYS
            Unit.WEEK -> LONGEST_WEEKS
            Unit.MONTH -> LONGEST_MONTHS
            Unit.YEAR -> LONGEST_YEARS
        }

        /** [every] of [unit], kept at least one and at most [longest]. */
        fun of(every: Int, unit: Unit): RecurrenceInterval = RecurrenceInterval(every.coerceIn(1, longest(unit)), unit)

        fun days(count: Int): RecurrenceInterval = of(count, Unit.DAY)

        fun weeks(count: Int): RecurrenceInterval = of(count, Unit.WEEK)

        fun months(count: Int): RecurrenceInterval = of(count, Unit.MONTH)

        fun years(count: Int): RecurrenceInterval = of(count, Unit.YEAR)
    }
}
