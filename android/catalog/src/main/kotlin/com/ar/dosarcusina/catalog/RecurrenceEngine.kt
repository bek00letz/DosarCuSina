package com.ar.dosarcusina.catalog

import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.archive.v3.ObligationBlueprint
import com.ar.dosarcusina.archive.v3.RecurrenceRule
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.MonthDay
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull

/**
 * When a deadline is first due, as the iOS app's `RecurrenceEngine`
 * (ios/DosarCuSina/Services/Obligations/RecurrenceEngine.swift): the part the household's own
 * deadlines and a new section's deadlines need ([firstDue]). The rest of the engine (the next due
 * day once a cycle is done, the ITP's interval, a counter's due reading) comes with Phase 3's
 * engines, which extend this object rather than make a second one.
 */
object RecurrenceEngine {
    private const val DAYS_IN_A_WEEK = 7
    private const val MONTHS_IN_A_YEAR = 12

    /**
     * The first due day of a deadline made from [blueprint] on [today], by its `firstDue` rule:
     * a field's day ([values]) and its offset, an interval after today, the next of its fixed dates;
     * none when the person is to be asked, or the rule says nothing this build reads.
     */
    fun firstDue(blueprint: ObligationBlueprint, values: FieldValues, today: CalendarDay): CalendarDay? {
        val rule = blueprint.firstDue as? JsonObject ?: return null
        return when (rule.text("type")) {
            "field" -> fieldDay(rule, values)
            "afterInterval" -> afterInterval(rule, today)
            "nextFixedDate" -> fixedDates(blueprint)?.let { nextFixedDate(onOrAfter = today, dates = it) }
            else -> null
        }
    }

    /** A field's day and its offset. */
    private fun fieldDay(rule: JsonObject, values: FieldValues): CalendarDay? {
        val day = rule.text("field")?.let { (values[it] as? FieldValue.Day)?.value }
        return day?.addingDays(rule.number("offsetDays") ?: 0)
    }

    /** An interval after [today]. */
    private fun afterInterval(rule: JsonObject, today: CalendarDay): CalendarDay? {
        val every = rule.number("every")
        val unit = rule.text("unit")?.takeIf { it in RecurrenceRule.UNITS }
        return if (every == null || unit == null) null else add(every, unit, today)
    }

    /** The fixed dates a blueprint repeats on, when it does. */
    private fun fixedDates(blueprint: ObligationBlueprint): List<MonthDay>? =
        (blueprint.recurrence?.let(RecurrenceRule.codec::decode) as? RecurrenceRule.FixedDates)
            ?.dates?.takeIf { it.isNotEmpty() }

    /**
     * [day] moved by [every] of [unit] (`day`, `week`, `month`, `year`): months and years by the one
     * month arithmetic ([CalendarDay.addingMonths]). An interval of none (or fewer) never moves a day.
     */
    fun add(every: Int, unit: String, day: CalendarDay, dayOfMonth: Int? = null): CalendarDay {
        if (every <= 0) return day
        return when (unit) {
            "day" -> day.addingDays(every)
            "week" -> day.addingDays(every * DAYS_IN_A_WEEK)
            "month" -> day.addingMonths(every, dayOfMonth)
            "year" -> day.addingMonths(every * MONTHS_IN_A_YEAR, dayOfMonth)
            else -> day
        }
    }

    /** The first of [dates] strictly after [after]. */
    fun nextFixedDateAfter(after: CalendarDay, dates: List<MonthDay>): CalendarDay =
        nextFixedDate(onOrAfter = after.addingDays(1), dates = dates)

    /** The first of [dates] on or after [onOrAfter]. */
    fun nextFixedDate(onOrAfter: CalendarDay, dates: List<MonthDay>): CalendarDay =
        listOf(onOrAfter.year, onOrAfter.year + 1).flatMap { year -> dates.map { it.day(year) } }
            .filter { it >= onOrAfter }.minOrNull() ?: onOrAfter

    private fun JsonObject.text(name: String): String? =
        (this[name] as? JsonPrimitive)?.takeIf { it.isString }?.content

    private fun JsonObject.number(name: String): Int? =
        (this[name] as? JsonPrimitive)?.takeIf { !it.isString }?.intOrNull
}
