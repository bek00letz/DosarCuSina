package com.ar.dosarcusina.core.values

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.math.BigDecimal
import java.math.RoundingMode

/**
 * An amount of money in one currency, as the iOS app's `Money`
 * (ios/DosarCuSina/Models/Values/Money.swift), as far as the archive needs it: the value and
 * its stored form, `{"amount": "175.5", "currency": "RON"}`. The amount is a decimal string so
 * no platform loses precision on the way; amounts in different currencies are never added
 * together. How an amount is written for people comes with the wording.
 */
class Money(amount: BigDecimal, currency: String = DEFAULT_CURRENCY) {
    /** The amount, one form for one value (1.50 is 1.5). */
    val amount: BigDecimal = DecimalText.normalized(amount)

    /** ISO 4217 code, in capitals: `RON`, `EUR`, `USD`. */
    val currency: String = currency.uppercase()

    /** The amount as archives write it: plain, with a dot, to two decimals, half to even ("0.125" is "0.12"). */
    val amountString: String get() = DecimalText.write(amount.setScale(2, RoundingMode.HALF_EVEN))

    /** The stored form. */
    fun toJson(): JsonObject =
        JsonObject(mapOf("amount" to JsonPrimitive(amountString), "currency" to JsonPrimitive(currency)))

    override fun equals(other: Any?): Boolean = other is Money && other.amount == amount && other.currency == currency

    override fun hashCode(): Int = 31 * amount.hashCode() + currency.hashCode()

    override fun toString(): String = "$amountString $currency"

    companion object {
        const val DEFAULT_CURRENCY: String = "RON"

        /** Currencies offered first in pickers. Any ISO 4217 code is accepted. */
        val COMMON_CURRENCIES: List<String> = listOf("RON", "EUR", "USD")

        /**
         * The most significant digits an amount may have: what the iOS app's store keeps exactly
         * (it holds an amount through a Double), as `Money.mostDigits` says. Up to
         * 9.999.999.999.999,99 lei, or as many decimals as fit in the 15.
         */
        const val MOST_DIGITS: Int = 15

        /**
         * Whether the binder keeps [amount] exactly: at most [MOST_DIGITS] significant digits. What
         * is typed or read ([RomanianNumber.read] for money) and what a backup brings ([of]) both ask it.
         */
        fun keepsExactly(amount: BigDecimal): Boolean =
            amount.signum() == 0 || amount.abs().stripTrailingZeros().precision() <= MOST_DIGITS

        /**
         * An amount in the machine form archives and stored JSON use ("12.50"); null when it isn't
         * one, or has more digits than the binder keeps exactly ([keepsExactly]).
         */
        fun of(amountString: String, currency: String): Money? =
            RomanianNumber.canonical(amountString)?.takeIf(::keepsExactly)?.let { Money(it, currency) }

        /** The stored form read back: both keys text, the amount in machine form; null otherwise. */
        fun fromJson(element: JsonElement): Money? {
            val fields = element as? JsonObject ?: return null
            val currency = (fields["currency"] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return null
            val amount = (fields["amount"] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return null
            return of(amount, currency)
        }
    }
}
