package com.ar.dosarcusina.core.subscriptions

import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.Money
import com.ar.dosarcusina.core.values.RecurrenceInterval
import java.math.BigDecimal

/**
 * One bill a subscription received: the day it was issued and what it came to. The store fills one from each of a
 * subscription's history records of a payment that isn't a completion's (what capture logged).
 */
data class BillRecord(val day: CalendarDay, val amount: Money?)

/** How a subscription's bills move. */
data class BillTrend(
    /** The newest bill with an amount. */
    val last: BillRecord,
    /** How much more or less than the one before it in the same currency; null when there is none. */
    val change: Money?,
    val direction: Direction?,
    /** What a bill came to on average over the last 365 days, one amount per currency, in the currencies' order. */
    val averageLastYear: List<Money>,
) {
    enum class Direction { UP, DOWN, SAME }
}

/** A bill that hasn't come when it usually does: a calm note, never an alarm. */
data class MissingBill(
    /** When the last one came. */
    val lastDay: CalendarDay,
    /** When this one was expected. */
    val expectedDay: CalendarDay,
    /** How often the bills come: a week, a month, three months, a year. */
    val cycle: RecurrenceInterval,
)

/**
 * Pure questions about a subscription's bills, as the iOS app's `BillHistory`
 * (ios/DosarCuSina/Services/Subscriptions/BillHistory.swift): the trend of the amounts and whether one is missing.
 * Everything comes from the bills and the day it is asked on.
 */
object BillHistory {
    private const val DAYS_IN_A_YEAR = 365
    private const val DAYS_IN_A_WEEK = 7
    private const val DAYS_IN_A_MONTH = 30
    private const val MOST_GRACE_DAYS = 30

    /** A bill may come a third of its cycle late, rounded up. */
    private const val GRACE_PARTS = 3

    /**
     * The most a bill has come late before, counted in days past one cycle after the previous one, so a provider that
     * always bills a few days late isn't flagged: at most half its cycle, and never more than this.
     */
    internal const val USUAL_LATENESS_CAP = 15

    /**
     * After this many cycles without a bill, the note stops: the contract has likely ended or the bills go elsewhere.
     */
    internal const val CYCLES_TO_KEEP_SAYING = 2

    /** The trend of [bills] on [today]; null without a bill with an amount. Lei are never compared with euro. */
    fun trend(bills: List<BillRecord>, today: CalendarDay): BillTrend? {
        val priced = bills.filter { it.amount != null }.sortedBy { it.day }
        val last = priced.lastOrNull() ?: return null
        val amount = checkNotNull(last.amount)
        val previous = priced.dropLast(1).lastOrNull { it.amount?.currency == amount.currency }?.amount
        val change = previous?.let { Money(amount.amount.subtract(it.amount), amount.currency) }
        val direction = change?.let {
            when (it.amount.signum()) {
                1 -> BillTrend.Direction.UP
                -1 -> BillTrend.Direction.DOWN
                else -> BillTrend.Direction.SAME
            }
        }
        val yearAgo = today.addingDays(-DAYS_IN_A_YEAR)
        val recent = priced.filter { it.day > yearAgo }.mapNotNull { it.amount }
        val averages = recent.groupBy { it.currency }.toSortedMap().map { (currency, amounts) ->
            val total = amounts.fold(BigDecimal.ZERO) { sum, money -> sum.add(money.amount) }
            Money(SubscriptionMath.cents(SubscriptionMath.divide(total, amounts.size)), currency)
        }
        return BillTrend(last, change, direction, averages)
    }

    /** How many days a cycle lasts, roughly, for how late a bill may come: a week is 7, a month 30, a year 365. */
    internal fun roughDays(cycle: RecurrenceInterval): Int {
        val unit = when (cycle.unit) {
            RecurrenceInterval.Unit.DAY -> 1
            RecurrenceInterval.Unit.WEEK -> DAYS_IN_A_WEEK
            RecurrenceInterval.Unit.MONTH -> DAYS_IN_A_MONTH
            RecurrenceInterval.Unit.YEAR -> DAYS_IN_A_YEAR
        }
        return unit * cycle.every.coerceAtLeast(1)
    }

    /**
     * How many days past its usual day a bill may come before it is worth a note: a third of its cycle, so ten for a
     * monthly bill and three for a weekly one, at most thirty.
     */
    internal fun graceDays(cycle: RecurrenceInterval): Int =
        minOf((roughDays(cycle) + GRACE_PARTS - 1) / GRACE_PARTS, MOST_GRACE_DAYS)

    /** The bill that should have come by [today] and hasn't, if any, for bills that come every [cycle]. */
    fun missing(bills: List<BillRecord>, cycle: RecurrenceInterval, today: CalendarDay): MissingBill? {
        val days = bills.map { it.day }.distinct().sorted()
        val last = days.lastOrNull() ?: return null
        fun cycleAfter(day: CalendarDay, cycles: Int = 1): CalendarDay = cycle.times(cycles).after(day)
        val latenessCap = minOf(USUAL_LATENESS_CAP, roughDays(cycle) / 2)
        val usualLateness = days.zipWithNext { previous, next -> cycleAfter(previous).daysTo(next) }
            .maxOrNull()?.coerceIn(0, latenessCap.coerceAtLeast(0)) ?: 0
        val expected = cycleAfter(last)
        val late = expected.daysTo(today)
        val worthANote = late > graceDays(cycle) + usualLateness && today < cycleAfter(last, CYCLES_TO_KEEP_SAYING + 1)
        return if (worthANote) MissingBill(last, expected, cycle) else null
    }
}
