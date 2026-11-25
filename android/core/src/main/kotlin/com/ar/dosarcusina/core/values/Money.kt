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

        /** An amount in the machine form archives and stored JSON use ("12.50"); null when it isn't one. */
        fun of(amountString: String, currency: String): Money? =
            RomanianNumber.canonical(amountString)?.let { Money(it, currency) }

        /** The stored form read back: both keys text, the amount in machine form; null otherwise. */
        fun fromJson(element: JsonElement): Money? {
            val fields = element as? JsonObject ?: return null
            val currency = (fields["currency"] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return null
            val amount = (fields["amount"] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return null
            return of(amount, currency)
        }
    }
}
