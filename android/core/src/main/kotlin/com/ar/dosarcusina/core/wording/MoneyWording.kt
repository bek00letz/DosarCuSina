package com.ar.dosarcusina.core.wording

import com.ar.dosarcusina.core.values.Money
import com.ar.dosarcusina.core.values.RomanianNumber
import java.math.BigDecimal
import java.math.RoundingMode

/** „1.250,50 lei”, „1.250,50 EUR”: an amount with two decimals, as the iOS app's `Money.formatted()`. */
fun Money.formatted(): String = MoneyWording.written(this, fractionDigits = 2)

/** „350 lei”, „1,50 lei”: without decimals when the amount is whole, as `Money.formattedCompact()`. */
fun Money.formattedCompact(): String =
    MoneyWording.written(this, fractionDigits = if (amount.stripTrailingZeros().scale() <= 0) 0 else 2)

/**
 * The one way an amount is written, as the iOS app's `Money` (ios/DosarCuSina/Models/Values/Money.swift)
 * and docs/COPY_GUIDE.md say: in lei for the leu („1.250,50 lei”, never „RON”), the number and its
 * unit kept on one line; any other currency by its code („1.250,50 EUR”). A whole number of lei
 * takes the leu's plural from the String Catalog ([wholeLei]): „1 leu”, „2 lei”, „20 de lei”; with
 * decimals it is always „lei” („1,50 lei”).
 */
object MoneyWording {
    private const val NO_BREAK_SPACE = '\u00A0'

    /** A currency's name where it is chosen or shown alone: the leu as „lei”, never „RON”; any other by its code. */
    fun currencyName(code: String): String =
        if (code.uppercase() == Money.DEFAULT_CURRENCY) Word.app("lei").written() else code.uppercase()

    /** A whole number of lei written as [number] („1.250”), its plural form picked by [count], without its sign. */
    fun wholeLei(number: String, count: Long): String =
        Word.app("%@\u00A0%lld lei", Word.text(number), Word.count(count)).written()

    internal fun written(money: Money, fractionDigits: Int): String {
        val number = RomanianNumber.format(money.amount, fractionDigits, fractionDigits)
        if (money.currency != Money.DEFAULT_CURRENCY) return "$number$NO_BREAK_SPACE${money.currency}"
        val count = if (fractionDigits == 0) wholeCount(money.amount) else null
        return if (count != null) wholeLei(number, count) else Word.app("%@\u00A0lei", Word.text(number)).written()
    }

    /** The whole number of lei an amount is, without its sign; null when it doesn't fit. */
    private fun wholeCount(amount: BigDecimal): Long? {
        val whole = amount.abs().setScale(0, RoundingMode.HALF_UP)
        return if (whole < BigDecimal.valueOf(Long.MAX_VALUE)) whole.toLong() else null
    }
}
