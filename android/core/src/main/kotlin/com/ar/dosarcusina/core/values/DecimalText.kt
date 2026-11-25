package com.ar.dosarcusina.core.values

import java.math.BigDecimal
import java.math.BigInteger

/**
 * Decimal numbers in their machine form, as the iOS app's Foundation `Decimal` reads and writes
 * them, never through a Double: "1250.5", "-3", "0.0000001".
 *
 * Foundation's decimal keeps its digits in 128 bits (up to 39 of them): a longer number keeps
 * the digits that fit, the whole part's others becoming zeros and the fraction's others
 * dropped, as on the iPhone. Every amount and reading the app keeps fits many times over.
 */
object DecimalText {
    private val LARGEST_DIGITS: BigInteger = BigInteger.ONE.shiftLeft(128).subtract(BigInteger.ONE)

    /**
     * The number at the start of [text]: an optional `-`, ASCII digits, then an optional `.` and
     * more of them; what follows isn't read. Null when it starts with no digit to read.
     */
    fun read(text: String): BigDecimal? {
        var at = 0
        val negative = text.startsWith("-")
        if (negative) at++
        var digits = BigInteger.ZERO
        var exponent = 0
        var sawDigit = false
        while (at < text.length && text[at] in '0'..'9') {
            sawDigit = true
            val next = digits.multiply(BigInteger.TEN).add(BigInteger.valueOf((text[at] - '0').toLong()))
            if (next <= LARGEST_DIGITS) digits = next else exponent++
            at++
        }
        if (at < text.length && text[at] == '.') {
            at++
            while (at < text.length && text[at] in '0'..'9') {
                sawDigit = true
                val next = digits.multiply(BigInteger.TEN).add(BigInteger.valueOf((text[at] - '0').toLong()))
                if (next <= LARGEST_DIGITS) {
                    digits = next
                    exponent--
                }
                at++
            }
        }
        if (!sawDigit) return null
        val value = BigDecimal(digits, -exponent)
        return normalized(if (negative) value.negate() else value)
    }

    /** How Foundation's `Decimal` writes [value]: plain digits, no trailing zeros, "0" for zero. */
    fun write(value: BigDecimal): String = normalized(value).toPlainString()

    /** One form for one value: 1.50 and 1.5 are the same number. */
    fun normalized(value: BigDecimal): BigDecimal =
        if (value.signum() == 0) BigDecimal.ZERO else value.stripTrailingZeros()
}
