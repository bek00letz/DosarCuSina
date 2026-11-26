package com.ar.dosarcusina.core.urgency

import com.ar.dosarcusina.core.values.CalendarDay
import kotlin.math.abs

/**
 * How far ahead a reminder goes, as the person reads it, as the iOS app's `ReminderLead`
 * (ios/Shared/Urgency.swift). A lead of a whole number of months (30 days each, a year being
 * 365) is that many calendar months, so „Cu 6 luni înainte” fires on the same day of the month
 * six months before, through the one month arithmetic ([CalendarDay.addingMonths]). Any other
 * lead is days.
 */
sealed interface ReminderLead {
    /** The day this lead before [due] falls on. */
    fun dayBefore(due: CalendarDay): CalendarDay

    /** A lead of days. */
    data class Days(val days: Int) : ReminderLead {
        override fun dayBefore(due: CalendarDay): CalendarDay = due.addingDays(-days)
    }

    /** A lead of calendar months (a year is twelve). */
    data class Months(val months: Int) : ReminderLead {
        override fun dayBefore(due: CalendarDay): CalendarDay = due.addingMonths(-months)
    }

    companion object {
        /**
         * The longest a reminder's lead, a grace or a travel margin can be, in days: a hundred
         * years. A number from outside (a backup, another device) is held to it where it is
         * read, so every day worked out from it is a day the calendar has.
         */
        const val LONGEST_DAYS: Int = 36_500

        private const val DAYS_IN_MONTH = 30
        private const val DAYS_IN_YEAR = 365
        private const val MONTHS_IN_YEAR = 12

        /** [days] as a length the app counts with: none below zero, at most [LONGEST_DAYS]. */
        fun bounded(days: Int): Int = days.coerceIn(0, LONGEST_DAYS)

        /** The lead of [days] days, by its size (a negative lead is the same lead), held to the longest. */
        fun of(days: Int): ReminderLead {
            val size = abs(days.toLong()).coerceAtMost(LONGEST_DAYS.toLong()).toInt()
            return when {
                size >= DAYS_IN_YEAR && size % DAYS_IN_YEAR == 0 -> Months(size / DAYS_IN_YEAR * MONTHS_IN_YEAR)
                size >= DAYS_IN_MONTH && size % DAYS_IN_MONTH == 0 -> Months(size / DAYS_IN_MONTH)
                else -> Days(size)
            }
        }
    }
}
