package com.ar.dosarcusina.core.wording

import com.ar.dosarcusina.core.values.MeasurementUnit
import com.ar.dosarcusina.core.values.RomanianNumber
import java.math.BigDecimal
import kotlin.math.abs

/**
 * A number with its unit, as the iOS app's `MeasurementUnit.written` and `after`
 * (ios/DosarCuSina/Models/Values/MeasurementUnit.swift): „45.724 km”, „12,5 m³”, „1.250 de
 * cafele”, kept on one line with a no-break space; the number alone when there is no unit.
 */
object UnitWording {
    private const val NO_BREAK_SPACE = '\u00A0'

    /** [value] written with between [fewestFractionDigits] and [mostFractionDigits] decimals, then its [unit]. */
    fun written(
        value: Double,
        unit: MeasurementUnit?,
        fewestFractionDigits: Int = 0,
        mostFractionDigits: Int = 1,
    ): String {
        // The double's shortest decimal text, as iOS's Decimal(Double) takes it: 0.35 is 0,4 to one decimal.
        val number = RomanianNumber.format(BigDecimal.valueOf(value), fewestFractionDigits, mostFractionDigits)
        return if (unit == null) number else after(unit, number, value)
    }

    /**
     * [number], already written („1.250”), followed by [unit]: a symbol as it is („45.724 km”); a
     * counted word („cafele”, „luni”) counted as Romanian counts it, from the String Catalog's
     * plural forms: „1 cafea”, „2 cafele”, „20 de cafele”, „101 cafele”. A value with decimals
     * takes the word as after 2 („1,5 luni”). [value] only chooses the form.
     */
    fun after(unit: MeasurementUnit, number: String, value: Double): String {
        val count = wholeCount(value)
        val key = when (unit) {
            MeasurementUnit.SHOTS -> "%@\u00A0%lld cafele"
            MeasurementUnit.MONTHS -> "%@\u00A0%lld luni"
            else -> null
        }
        if (key == null || count == null) return "$number$NO_BREAK_SPACE${label(unit)}"
        return Word.app(key, Word.text(number), Word.count(count)).written()
    }

    /** What a person sees after a number: the catalog's word for a counted unit, else [MeasurementUnit.label]. */
    fun label(unit: MeasurementUnit): String = when (unit) {
        MeasurementUnit.SHOTS -> Word.app("cafele").written()
        MeasurementUnit.MONTHS -> Word.app("luni").written()
        else -> unit.label
    }

    /** The whole number [value] is, without its sign, when it has no decimals and fits. */
    private fun wholeCount(value: Double): Long? {
        val magnitude = abs(value)
        val whole = Math.rint(magnitude) == magnitude && magnitude < Long.MAX_VALUE.toDouble()
        return if (whole) magnitude.toLong() else null
    }
}
