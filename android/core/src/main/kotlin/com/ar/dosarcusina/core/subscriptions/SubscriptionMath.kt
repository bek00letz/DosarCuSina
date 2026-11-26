package com.ar.dosarcusina.core.subscriptions

import com.ar.dosarcusina.core.values.Money
import com.ar.dosarcusina.core.values.RecurrenceInterval
import java.math.BigDecimal
import java.math.MathContext
import java.math.RoundingMode

/**
 * What subscriptions cost per month, as the iOS app's `SubscriptionMath`
 * (ios/DosarCuSina/Services/Templates/SubscriptionMath.swift): worked out in decimals, never through a `Double`,
 * and kept per currency.
 */
object SubscriptionMath {
    private const val DAYS_IN_A_YEAR = 365
    private const val WEEKS_IN_A_YEAR = 52
    private const val MONTHS_IN_A_YEAR = 12

    /** Foundation's `Decimal` keeps 38 digits; a division here keeps as many before it is rounded to cents. */
    private const val DECIMAL_DIGITS = 38
    private val DECIMAL = MathContext(DECIMAL_DIGITS, RoundingMode.HALF_UP)

    /**
     * The monthly equivalent of one subscription's [price], paid every [cycle] (its stored cycle, as text), or null
     * without a price. A contract billed by use (gas, electricity) has no fixed price: with [usingLastBill], its
     * [lastBill] stands in for it.
     */
    fun monthlyEquivalent(price: Money?, lastBill: Money?, cycle: String?, usingLastBill: Boolean = true): Money? {
        val paid = price ?: lastBill.takeIf { usingLastBill } ?: return null
        return monthly(paid, BillingCycle.interval(cycle))
    }

    /**
     * What [price], paid once every [cycle], comes to a month: a year is twelve months, and a year has 52 weeks and
     * 365 days, so a weekly price is 52 of them over twelve months. Rounded to cents, half away from zero, as
     * Foundation's `NSDecimalRound(.plain)`.
     */
    fun monthly(price: Money, cycle: RecurrenceInterval): Money {
        val every = BigDecimal(cycle.every)
        val year = BigDecimal(MONTHS_IN_A_YEAR).multiply(every)
        val perMonth = when (cycle.unit) {
            RecurrenceInterval.Unit.DAY -> price.amount.multiply(BigDecimal(DAYS_IN_A_YEAR)).divide(year, DECIMAL)
            RecurrenceInterval.Unit.WEEK -> price.amount.multiply(BigDecimal(WEEKS_IN_A_YEAR)).divide(year, DECIMAL)
            RecurrenceInterval.Unit.MONTH -> price.amount.divide(every, DECIMAL)
            RecurrenceInterval.Unit.YEAR -> price.amount.divide(year, DECIMAL)
        }
        return Money(cents(perMonth), price.currency)
    }

    /** [amount] rounded to cents, half away from zero, as the iOS app's `Decimal.rounded(scale: 2)`. */
    internal fun cents(amount: BigDecimal): BigDecimal = amount.setScale(2, RoundingMode.HALF_UP)

    /** A division the way Foundation's `Decimal` makes it, before it is rounded. */
    internal fun divide(amount: BigDecimal, by: Int): BigDecimal = amount.divide(BigDecimal(by), DECIMAL)
}
