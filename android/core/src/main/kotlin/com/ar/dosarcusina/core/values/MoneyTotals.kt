package com.ar.dosarcusina.core.values

import java.math.BigDecimal

/**
 * Sums of money kept apart by currency, as the iOS app's `MoneyTotals`
 * (ios/DosarCuSina/Models/Values/Money.swift): what „Mai târziu” says it will cost, never one
 * total across currencies.
 */
class MoneyTotals private constructor(
    /** The sum in each currency, by its code. */
    val byCurrency: Map<String, BigDecimal>,
) {
    /** Nothing to say: every currency sums to zero. */
    val isEmpty: Boolean get() = byCurrency.values.all { it.signum() == 0 }

    /** One [Money] per currency that isn't zero, the default currency first, then by code. */
    val amounts: List<Money>
        get() = byCurrency.filterValues { it.signum() != 0 }
            .map { (currency, amount) -> Money(amount, currency) }
            .sortedWith(compareBy<Money> { it.currency != Money.DEFAULT_CURRENCY }.thenBy { it.currency })

    /** The sum in [currency]; zero when there is none. */
    fun amount(currency: String): BigDecimal = byCurrency[currency.uppercase()] ?: BigDecimal.ZERO

    /** These sums with [money] added to its currency's. */
    operator fun plus(money: Money): MoneyTotals {
        val sums = byCurrency.toMutableMap()
        sums[money.currency] = (sums[money.currency] ?: BigDecimal.ZERO) + money.amount
        return MoneyTotals(sums)
    }

    override fun equals(other: Any?): Boolean = other is MoneyTotals && amounts == other.amounts

    override fun hashCode(): Int = amounts.hashCode()

    override fun toString(): String = amounts.joinToString(" · ")

    companion object {
        /** No money at all. */
        val EMPTY: MoneyTotals = MoneyTotals(emptyMap())

        /** The sums of [values]. */
        fun of(values: Iterable<Money>): MoneyTotals = values.fold(EMPTY, MoneyTotals::plus)
    }
}
