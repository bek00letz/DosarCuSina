package com.ar.dosarcusina.catalog

import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.archive.v3.ObligationBlueprint
import com.ar.dosarcusina.archive.v3.RecurrenceRule
import com.ar.dosarcusina.core.readings.Reading
import com.ar.dosarcusina.core.readings.ReadingSeries
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.DosarCalendar
import com.ar.dosarcusina.core.values.MonthDay
import com.ar.dosarcusina.core.values.RecurrenceInterval
import com.ar.dosarcusina.core.values.option
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import kotlin.math.ceil

/** What the engine knows about a section when it works out the next date, as the iOS app's `RecurrenceContext`. */
data class RecurrenceContext(
    val assetValues: FieldValues = FieldValues(),
    /** Counter readings (odometer, shots), oldest first. */
    val readings: List<Reading> = emptyList(),
    /** The counter now, when known. */
    val currentMetric: Double? = null,
    /**
     * The day of the month a series counted from its due dates keeps (31 for "the 31st"), from
     * [RecurrenceEngine.seriesStart]. Null uses the due day's own.
     */
    val seriesDayOfMonth: Int? = null,
    /**
     * Every cycle is money still owed (a month's rent, a tax installment), so one "Gata" closes one
     * cycle even when it was done after the next was due. Otherwise a series counted from its due dates
     * moves to its first day after the day it was done.
     */
    val missedCyclesStayOwed: Boolean = false,
)

/** The next cycle of a repeating deadline: its due day and, for one counted by a counter, the reading it is due at. */
data class NextDue(val day: CalendarDay, val metric: Double? = null)

/** One completion as the series sees it: the cycle it closed and the due day it moved to. */
data class SeriesStep(val cycle: CalendarDay?, val next: CalendarDay?)

/**
 * Pure date math for deadlines, as the iOS app's `RecurrenceEngine`
 * (ios/DosarCuSina/Services/Obligations/RecurrenceEngine.swift): first due days from blueprints and the
 * next due day after a completion. All calendar arithmetic is [CalendarDay]'s, and one calendar step is
 * [RecurrenceInterval.after]'s: month ends and 29 February are handled once, there.
 *
 * A series counted from its due dates remembers its day of the month: every date is that day, or the
 * month's last day when the month is shorter, so a payment on the 31st is due on 28 February and on
 * 31 March again.
 *
 * The time zone only counts days between counter readings (a counter's projection); everything else is
 * days alone.
 */
// The engine's whole surface, one function per rule, as the iOS one.
@Suppress("TooManyFunctions")
object RecurrenceEngine {
    private const val MONTHS_IN_A_YEAR = 12
    private const val DAYS_IN_A_WEEK = 7
    private const val SECONDS_A_DAY = 86_400.0
    private const val NANOS_A_SECOND = 1e9

    /** The least time between two readings a counter's rate is read over, in days. */
    private const val SHORTEST_RATE_DAYS = 0.001

    /** A car is inspected every two years until it is this old, then every year. */
    private const val ITP_YOUNG_CAR_YEARS = 12

    /** How often a car that carries passengers for money is inspected, in months. */
    private const val ITP_COMMERCIAL_MONTHS = 6

    /** The anchor of a rule counted from the day it was done. */
    private const val COMPLETION = "completion"

    /** The car's use that carries passengers for money (`VehicleUse.commercial`). */
    private const val COMMERCIAL_USE = "vehicleUse.commercial"

    /** Counter deadlines without a calendar fallback are checked again after this long. */
    val defaultMetricFallback: RecurrenceInterval = RecurrenceInterval.months(6)

    // Next cycle

    /** The next due day after completing the cycle due on [due] on [completedOn]; null for one that doesn't repeat. */
    fun nextDue(
        due: CalendarDay,
        completedOn: CalendarDay,
        rule: RecurrenceRule,
        context: RecurrenceContext = RecurrenceContext(),
        zone: ZoneId = DosarCalendar.zone(),
    ): NextDue? = when (rule) {
        RecurrenceRule.None, is RecurrenceRule.Unreadable -> null
        is RecurrenceRule.Interval -> {
            val interval = interval(rule)
            if (rule.anchor == COMPLETION) {
                NextDue(add(interval, completedOn))
            } else {
                // One cycle at a time while each is still owed; otherwise the first after the day it was done.
                val doneOn = if (context.missedCyclesStayOwed) due else completedOn
                NextDue(nextOfSeries(due, doneOn, interval, context.seriesDayOfMonth))
            }
        }
        is RecurrenceRule.FixedDates -> if (rule.dates.isEmpty()) {
            null
        } else {
            // The same rule: done after the next fixed date, the first one after the day it was done,
            // unless every installment is still owed.
            val doneOn = if (context.missedCyclesStayOwed) due else maxOf(due, completedOn)
            NextDue(nextFixedDateAfter(doneOn, rule.dates))
        }
        is RecurrenceRule.Metric -> nextByCounter(rule, completedOn, context, zone)
        is RecurrenceRule.Legal -> NextDue(add(itpInterval(context.assetValues, completedOn), completedOn))
    }

    /** A counter's next cycle: at the counter's target or the calendar fallback, whichever comes first. */
    private fun nextByCounter(
        rule: RecurrenceRule.Metric,
        completedOn: CalendarDay,
        context: RecurrenceContext,
        zone: ZoneId,
    ): NextDue {
        val reading = context.currentMetric ?: context.readings.lastOrNull()?.metric
        val fallbackDay = add(fallback(rule) ?: defaultMetricFallback, completedOn)
        if (reading == null) return NextDue(fallbackDay)
        val target = reading + rule.every
        val projected = projectedDay(reading, target, context.readings, completedOn, zone)
        val day = projected?.let { minOf(it, fallbackDay) } ?: fallbackDay
        return NextDue(maxOf(day, completedOn.addingDays(1)), target)
    }

    /**
     * The day the counter reaches [target] from [current] on [completedOn], at the rate its readings
     * moved, as the iOS app's `CadenceCalculator.projectTelemetryDueDate`: on the day for a target
     * already passed, at most a hundred years on; null when the readings give no rate.
     */
    private fun projectedDay(
        current: Double,
        target: Double,
        readings: List<Reading>,
        completedOn: CalendarDay,
        zone: ZoneId,
    ): CalendarDay? {
        val remaining = target - current
        if (remaining <= 0) return completedOn
        val progress = ReadingSeries(readings).progress { first, last -> daysBetween(first, last, zone) }
            ?.takeIf { it.days > SHORTEST_RATE_DAYS && it.distance > 0 } ?: return null
        val rate = progress.distance / progress.days
        val raw = ceil(remaining / rate)
        val longest = RecurrenceInterval.longest(RecurrenceInterval.Unit.DAY)
        val days = if (raw.isNaN() || raw.isInfinite() || raw > longest) longest else maxOf(1, raw.toInt())
        return completedOn.addingDays(days)
    }

    /**
     * The days between two readings: the calendar days between the days they were read on, with the
     * part of a day between their times, as the iOS projection counts them; within one day, by the hour.
     */
    private fun daysBetween(first: Instant, last: Instant, zone: ZoneId): Double {
        val firstDay = CalendarDay.of(first, zone)
        val lastDay = CalendarDay.of(last, zone)
        val whole = firstDay.daysTo(lastDay)
        if (whole <= 0) return seconds(Duration.between(first, last)) / SECONDS_A_DAY
        val intoFirst = seconds(Duration.between(firstDay.startOfDay(zone), first))
        val intoLast = seconds(Duration.between(lastDay.startOfDay(zone), last))
        return whole + (intoLast - intoFirst) / SECONDS_A_DAY
    }

    private fun seconds(duration: Duration): Double = duration.seconds + duration.nano / NANOS_A_SECOND

    // First cycle

    /**
     * The first due day of a deadline made from [blueprint] on [today], by its `firstDue` rule: a field's
     * day ([values]) and its offset, an interval after today, the next of its fixed dates; none when the
     * person is to be asked, or the rule says nothing this build reads.
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

    /** An interval after [today]; a unit this build doesn't know asks, as an unknown rule does. */
    private fun afterInterval(rule: JsonObject, today: CalendarDay): CalendarDay? {
        val every = rule.number("every") ?: return null
        val unit = rule.text("unit")?.let(RecurrenceInterval.Unit::stored) ?: return null
        return add(RecurrenceInterval.of(every, unit), today)
    }

    /** The fixed dates a blueprint repeats on, when it does. */
    private fun fixedDates(blueprint: ObligationBlueprint): List<MonthDay>? =
        (blueprint.recurrence?.let(RecurrenceRule.codec::decode) as? RecurrenceRule.FixedDates)
            ?.dates?.takeIf { it.isNotEmpty() }

    // Series

    /**
     * The next due day of a series counted from its due dates, once the cycle due on [due] is done on
     * [doneOn]: the first of its days after both ([due], then one step at a time, on the series' day of
     * the month). Done early or on time it is one step on; done after one or more of its next days have
     * passed, those are left behind with the cycle it closed, so "Gata" never leaves the deadline overdue
     * the moment it is done.
     */
    fun nextOfSeries(
        due: CalendarDay,
        doneOn: CalendarDay,
        interval: RecurrenceInterval,
        dayOfMonth: Int?,
    ): CalendarDay {
        val oneStep = add(interval, due, dayOfMonth)
        if (oneStep > doneOn) return oneStep
        // Each step counted from the due day with the series' day, so a month's end never drifts.
        val seriesDay = dayOfMonth ?: due.day
        fun step(count: Int): CalendarDay = add(interval.times(count), due, seriesDay)
        // A first guess from how far it was done, then on until it is after that day.
        val months = (doneOn.year - due.year) * MONTHS_IN_A_YEAR + (doneOn.month - due.month)
        val behind = when (interval.unit) {
            RecurrenceInterval.Unit.DAY -> due.daysTo(doneOn) / interval.every
            RecurrenceInterval.Unit.WEEK -> due.daysTo(doneOn) / (interval.every * DAYS_IN_A_WEEK)
            RecurrenceInterval.Unit.MONTH -> months / interval.every
            RecurrenceInterval.Unit.YEAR -> months / (interval.every * MONTHS_IN_A_YEAR)
        }
        var count = maxOf(1, behind)
        while (step(count) <= doneOn) count += 1
        return step(count)
    }

    /**
     * The first due day of the unbroken series [current] belongs to. Walks back through the completions,
     * newest first, while each one moved the date to the cycle after it by [interval]; a due day the
     * person set by hand, or a step another rule took (before the person changed how it repeats), starts
     * a new series. Its day of the month is the day the series keeps.
     */
    fun seriesStart(current: CalendarDay, completions: List<SeriesStep>, interval: RecurrenceInterval): CalendarDay {
        var start = current
        for (step in completions) {
            val cycle = step.cycle?.takeIf { step.next == start && isStep(interval, it, start) } ?: break
            start = cycle
        }
        return start
    }

    /**
     * Whether [next] is a whole number of [interval]s after [cycle] in a series (one, or more when it was
     * done after its next due days): days and weeks exactly, months and years on the series' day or the
     * month's last day when it is shorter (31 January to 28 February, then 31 March).
     */
    fun isStep(interval: RecurrenceInterval, cycle: CalendarDay, next: CalendarDay): Boolean {
        if (cycle >= next) return false
        return when (interval.unit) {
            RecurrenceInterval.Unit.DAY, RecurrenceInterval.Unit.WEEK -> {
                val period = interval.every * if (interval.unit == RecurrenceInterval.Unit.WEEK) DAYS_IN_A_WEEK else 1
                cycle.daysTo(next) % period == 0
            }
            RecurrenceInterval.Unit.MONTH, RecurrenceInterval.Unit.YEAR -> {
                val months = (next.year - cycle.year) * MONTHS_IN_A_YEAR + (next.month - cycle.month)
                val period = interval.every * if (interval.unit == RecurrenceInterval.Unit.YEAR) MONTHS_IN_A_YEAR else 1
                // The series' day is at least the later of the two days a clamped month shows.
                months > 0 && months % period == 0 &&
                    cycle.addingMonths(months, dayOfMonth = maxOf(cycle.day, next.day)) == next
            }
        }
    }

    /**
     * The day the cycle due on [due] began: one step of its rule before it (for a deadline counted from
     * when it was done, the day it was done, when it was done on time), or the fixed date before it. Null
     * for a rule whose cycle has no set length (none, a counter, a legal rule read from the section): its
     * leads all count. What `ReminderProfile.forCycle` reads.
     */
    fun cycleStart(due: CalendarDay, rule: RecurrenceRule): CalendarDay? = when (rule) {
        is RecurrenceRule.Interval -> {
            val interval = interval(rule)
            when (interval.unit) {
                RecurrenceInterval.Unit.DAY -> due.addingDays(-interval.every)
                RecurrenceInterval.Unit.WEEK -> due.addingDays(-interval.every * DAYS_IN_A_WEEK)
                RecurrenceInterval.Unit.MONTH -> due.addingMonths(-interval.every)
                RecurrenceInterval.Unit.YEAR -> due.addingMonths(-interval.every * MONTHS_IN_A_YEAR)
            }
        }
        is RecurrenceRule.FixedDates ->
            listOf(due.year - 1, due.year).flatMap { year -> rule.dates.map { it.day(year) } }
                .filter { it < due }.maxOrNull()
        else -> null
    }

    // Building blocks

    /**
     * [day] moved on by [interval]: the one calendar step ([RecurrenceInterval.after]). Months and years
     * land on [dayOfMonth] (the series' day), or the month's last day when it is shorter; without it, on
     * [day]'s own day.
     */
    fun add(interval: RecurrenceInterval, day: CalendarDay, dayOfMonth: Int? = null): CalendarDay =
        interval.after(day, dayOfMonth)

    /** The first of [dates] strictly after [after]. */
    fun nextFixedDateAfter(after: CalendarDay, dates: List<MonthDay>): CalendarDay =
        nextFixedDate(onOrAfter = after.addingDays(1), dates = dates)

    /** The first of [dates] on or after [onOrAfter]. */
    fun nextFixedDate(onOrAfter: CalendarDay, dates: List<MonthDay>): CalendarDay =
        listOf(onOrAfter.year, onOrAfter.year + 1).flatMap { year -> dates.map { it.day(year) } }
            .filter { it >= onOrAfter }.minOrNull() ?: onOrAfter

    /**
     * The ITP interval for a passenger car (OUG 195/2002, RNTR 1): every 6 months for ridesharing and
     * taxis; otherwise every 2 years while the car is at most 12 years old and every year after. An
     * unknown age gets the shorter interval, so a reminder is never late.
     */
    fun itpInterval(values: FieldValues, day: CalendarDay): RecurrenceInterval {
        val usage = (values[VehicleFields.USAGE] as? FieldValue.Text)?.value
        if (usage != null && usageOptions.option(usage)?.key == COMMERCIAL_USE) {
            return RecurrenceInterval.months(ITP_COMMERCIAL_MONTHS)
        }
        // A year no whole number holds (a backup's 1e19) is an unknown age.
        val year = (values[VehicleFields.YEAR] as? FieldValue.Number)?.value?.let(::wholeNumber)
            ?: return RecurrenceInterval.years(1)
        val age = runCatching { Math.subtractExact(day.year.toLong(), year) }.getOrNull()
            ?: return RecurrenceInterval.years(1)
        return if (age <= ITP_YOUNG_CAR_YEARS) RecurrenceInterval.years(2) else RecurrenceInterval.years(1)
    }

    /** The options of a car's use, as the catalog defines them (`VehicleUse.options`). */
    private val usageOptions by lazy {
        Catalog.builtIn.definition(BuiltInTemplates.Key.VEHICLE)?.sections.orEmpty()
            .flatMap { it.fields }.firstOrNull { it.key == VehicleFields.USAGE }?.options.orEmpty()
    }

    /**
     * [number] rounded to a whole number half away from zero, when a 64-bit whole number holds it
     * (`FieldValue.wholeNumberValue`); null past that range, for an infinity or for what isn't a number.
     */
    private fun wholeNumber(number: Double): Long? {
        if (!number.isFinite()) return null
        val rounded = BigDecimal(number).setScale(0, RoundingMode.HALF_UP)
        return if (rounded.toBigInteger().bitLength() < Long.SIZE_BITS) rounded.toLong() else null
    }

    /** A stored interval rule's step, held to the range an interval has ([RecurrenceInterval.of]). */
    fun interval(rule: RecurrenceRule.Interval): RecurrenceInterval =
        RecurrenceInterval.of(rule.every, requireNotNull(RecurrenceInterval.Unit.stored(rule.unit)))

    /** A counter rule's calendar fallback, when it has one. */
    fun fallback(rule: RecurrenceRule.Metric): RecurrenceInterval? {
        val every = rule.fallbackEvery ?: return null
        return RecurrenceInterval.of(every, requireNotNull(RecurrenceInterval.Unit.stored(rule.fallbackUnit.orEmpty())))
    }

    private fun JsonObject.text(name: String): String? =
        (this[name] as? JsonPrimitive)?.takeIf { it.isString }?.content

    private fun JsonObject.number(name: String): Int? =
        (this[name] as? JsonPrimitive)?.takeIf { !it.isString }?.intOrNull
}
