package com.ar.dosarcusina.core.wording

/** Romanian's plural categories (CLDR), the ones the String Catalogs hold: „o zi”, „2 zile”, „20 de zile”. */
enum class PluralCategory(val stored: String) {
    ONE("one"),
    FEW("few"),
    OTHER("other"),
}

/**
 * Which plural form a whole number takes in Romanian, by CLDR's rule, as iOS and Android pick
 * it: one for 1; few for 0 and for a number whose last two digits are 1 to 19 („2 zile”,
 * „101 zile”); other from 20 on („20 de zile”, „120 de zile”). A count's sign doesn't change it.
 */
object RomanianPlural {
    private const val HUNDRED = 100L
    private val FEW_ENDINGS = 1L..19L

    fun of(count: Long): PluralCategory {
        val n = if (count == Long.MIN_VALUE) Long.MAX_VALUE else kotlin.math.abs(count)
        return when {
            n == 1L -> PluralCategory.ONE
            n == 0L || n % HUNDRED in FEW_ENDINGS -> PluralCategory.FEW
            else -> PluralCategory.OTHER
        }
    }
}
