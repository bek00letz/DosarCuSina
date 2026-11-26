package com.ar.dosarcusina.core.history

import com.ar.dosarcusina.core.readings.Reading
import com.ar.dosarcusina.core.readings.ReadingSeries
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.Money
import com.ar.dosarcusina.core.values.RecurrenceInterval
import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor

/**
 * One line item with the facts of the record of history it belongs to, as plain values, as the iOS app's
 * `HistoryItemSnapshot` (ios/DosarCuSina/Services/History/MaintenanceLog.swift): what the maintenance log,
 * search and a section's Istoric read of a section's parts and jobs.
 */
data class HistoryItemSnapshot(
    /** The part or job it is: a catalog key or one of the person's own (`custom.…`); none for one not followed. */
    val componentKey: String?,
    val name: String,
    /** When the record it is in happened. */
    val occurredAt: Instant,
    /** The record of history it was done in. */
    val entryId: UUID = UUID.randomUUID(),
    val id: UUID = UUID.randomUUID(),
    val assetId: UUID? = null,
    /** The record's counter reading (km, engine hours) at the time. */
    val metricReading: Double? = null,
    val cost: Money? = null,
    val partBrandOrCode: String? = null,
    val supplierName: String? = null,
    /** Who did the record's work, by name, in order. */
    val providerNames: List<String> = emptyList(),
    val providerIds: List<UUID> = emptyList(),
)

/** The answer to "when did I last change it", as the iOS app's `ComponentOccurrence`. */
data class ComponentOccurrence(
    val entryId: UUID,
    val componentKey: String,
    val name: String,
    val date: Instant,
    /** The counter reading when it was done. */
    val metricAtTime: Double?,
    /** How far the counter has moved since ("acum 18.200 km"). */
    val metricSince: Double?,
    val daysSince: Int,
    val cost: Money?,
    val partBrandOrCode: String?,
    val supplierName: String?,
    val providerNames: List<String>,
    val providerIds: List<UUID>,
)

/** A guess at the next time a part needs doing, as the iOS app's `NextEstimate`. */
data class NextEstimate(
    val day: CalendarDay,
    val metric: Double?,
    val basis: Basis,
    /** How many past intervals it rests on; it shows as an estimate either way. */
    val sampleCount: Int,
) {
    enum class Basis(val raw: String) {
        /** From the typical distance and how fast the counter has been moving. */
        DISTANCE("distance"),

        /** From the typical time between jobs. */
        TIME("time"),
    }
}

/** How often a part is usually replaced, from the section's own history, as the iOS app's `TypicalInterval`. */
data class TypicalInterval(
    /** The median counter distance between replacements. */
    val metric: Double?,
    /** The median days between replacements. */
    val days: Int?,
    /** How many replacements the estimate rests on. */
    val sampleCount: Int,
)

/**
 * Pure questions about a section's maintenance history, as the iOS app's `MaintenanceLog`: the one place
 * that says when a part was last done, how often it usually is and when it will probably be again. Search,
 * a section's Istoric and the visit form read it; none works it out again. How far a counter moved is
 * counted over its counters ([ReadingSeries.distance]), so a new meter or dashboard is never a drop.
 */
object MaintenanceLog {
    private const val DAYS_A_MONTH = 30.0

    /** The fewest days the readings must span before a pace is said. */
    const val MINIMUM_SPAN_DAYS = 30

    /** Every time [componentKey] was done, newest first. */
    @Suppress("LongParameterList") // The iOS question's own parts, each with its default.
    fun occurrences(
        componentKey: String,
        items: List<HistoryItemSnapshot>,
        now: Instant,
        zone: ZoneId,
        currentMetric: Double? = null,
        readings: List<Reading> = emptyList(),
    ): List<ComponentOccurrence> {
        val today = CalendarDay.of(now, zone)
        val series = ReadingSeries(readings)
        return newestFirst(componentKey, items).map { item ->
            val since = if (currentMetric != null && item.metricReading != null) {
                series.distance(Reading(item.occurredAt, item.metricReading), Reading(now, currentMetric))
            } else {
                null
            }
            ComponentOccurrence(
                entryId = item.entryId, componentKey = componentKey, name = item.name, date = item.occurredAt,
                metricAtTime = item.metricReading, metricSince = since,
                daysSince = CalendarDay.of(item.occurredAt, zone).daysTo(today),
                cost = item.cost, partBrandOrCode = item.partBrandOrCode, supplierName = item.supplierName,
                providerNames = item.providerNames, providerIds = item.providerIds,
            )
        }
    }

    /** The last time [componentKey] was done; none when it never was. */
    @Suppress("LongParameterList") // The iOS question's own parts, each with its default.
    fun lastOccurrence(
        componentKey: String,
        items: List<HistoryItemSnapshot>,
        now: Instant,
        zone: ZoneId,
        currentMetric: Double? = null,
        readings: List<Reading> = emptyList(),
    ): ComponentOccurrence? = occurrences(componentKey, items, now, zone, currentMetric, readings).firstOrNull()

    /**
     * The line item of the last time [componentKey] was done, as [lastOccurrence] finds it: what a reader
     * that needs no counter or day count takes (search's results).
     */
    fun lastItem(componentKey: String, items: List<HistoryItemSnapshot>): HistoryItemSnapshot? =
        newestFirst(componentKey, items).firstOrNull()

    /** Parts and jobs that have history, newest activity first. */
    fun trackedComponents(items: List<HistoryItemSnapshot>): List<String> {
        val latest = LinkedHashMap<String, Instant>()
        for (item in items) {
            val key = item.componentKey ?: continue
            val known = latest[key]
            if (known == null || item.occurredAt > known) latest[key] = item.occurredAt
        }
        return latest.entries.sortedByDescending { it.value }.map { it.key }
    }

    /**
     * The median gap between consecutive replacements, in counter units and days. Needs at least two
     * occurrences. The distance between two jobs is counted over [readings]' counters, so one before a new
     * meter or dashboard and one after still pair.
     */
    fun typicalInterval(
        componentKey: String,
        items: List<HistoryItemSnapshot>,
        zone: ZoneId,
        readings: List<Reading> = emptyList(),
    ): TypicalInterval? {
        val ordered = items.filter { it.componentKey == componentKey }.sortedBy { it.occurredAt }
        if (ordered.size < 2) return null
        val series = ReadingSeries(readings)
        val pairs = ordered.zipWithNext()
        val days = pairs.map { (a, b) ->
            CalendarDay.of(a.occurredAt, zone).daysTo(CalendarDay.of(b.occurredAt, zone))
        }
        val metrics = pairs.mapNotNull { (a, b) ->
            val from = a.metricReading ?: return@mapNotNull null
            val to = b.metricReading ?: return@mapNotNull null
            series.distance(Reading(a.occurredAt, from), Reading(b.occurredAt, to)).takeIf { it > 0 }
        }
        val typicalDays = median(days.map(Int::toDouble))?.let { roundedAwayFromZero(it).toInt() }
        return TypicalInterval(median(metrics), typicalDays, ordered.size - 1)
    }

    /**
     * How far the counter moves in 30 days, from readings that span at least [minimumSpanDays], over the
     * one cleaned series ([ReadingSeries.progress]): a reading that breaks the order is skipped, and each
     * counter counts on its own. None when there isn't enough to say honestly.
     */
    fun monthlyRate(readings: List<Reading>, minimumSpanDays: Int = MINIMUM_SPAN_DAYS): Double? {
        val progress = ReadingSeries(readings).progress() ?: return null
        val honest = progress.days >= minimumSpanDays && progress.distance > 0
        return if (honest) progress.distance / progress.days * DAYS_A_MONTH else null
    }

    /**
     * When [componentKey] will probably need doing again, from its own history: by the typical distance
     * and the recent pace of the counter when both are known, else by the typical time between jobs. None
     * with fewer than two past jobs: one job is not a pattern.
     */
    @Suppress("LongParameterList") // The iOS question's own parts, each with its default.
    fun nextEstimate(
        componentKey: String,
        items: List<HistoryItemSnapshot>,
        now: Instant,
        zone: ZoneId,
        readings: List<Reading> = emptyList(),
        currentMetric: Double? = null,
    ): NextEstimate? {
        val current = currentMetric ?: ReadingSeries(readings).current
        val typical = typicalInterval(componentKey, items, zone, readings) ?: return null
        val last = lastOccurrence(componentKey, items, now, zone, current, readings) ?: return null
        val today = CalendarDay.of(now, zone)
        val dueMetric = dueMetric(current, last, typical)
        // A pace that puts the job further away than anything repeats says nothing honest: by time instead.
        val rate = monthlyRate(readings)
        val days = if (dueMetric != null && rate != null && current != null) {
            days(roundedAwayFromZero((dueMetric - current) / rate * DAYS_A_MONTH))
        } else {
            null
        }
        return when {
            days != null -> NextEstimate(today.addingDays(maxOf(0, days)), dueMetric, NextEstimate.Basis.DISTANCE,
                typical.sampleCount)
            typical.days != null -> NextEstimate(
                CalendarDay.of(last.date, zone).addingDays(typical.days), dueMetric, NextEstimate.Basis.TIME,
                typical.sampleCount,
            )
            else -> null
        }
    }

    private fun newestFirst(componentKey: String, items: List<HistoryItemSnapshot>): List<HistoryItemSnapshot> =
        items.filter { it.componentKey == componentKey }.sortedByDescending { it.occurredAt }

    /**
     * A number of days worked out from a pace, when it is a whole number no further than the longest anything
     * repeats; none otherwise (not a number, or centuries away).
     */
    internal fun days(value: Double): Int? {
        val longest = RecurrenceInterval.longest(RecurrenceInterval.Unit.DAY)
        if (!value.isFinite() || abs(value) > longest) return null
        return value.toInt()
    }

    internal fun median(values: List<Double>): Double? {
        if (values.isEmpty()) return null
        val sorted = values.sorted()
        val middle = sorted.size / 2
        return if (sorted.size % 2 == 0) (sorted[middle - 1] + sorted[middle]) / 2 else sorted[middle]
    }
}

/**
 * Where the counter will be when [last]'s part is due again: on the counter in use now, what is left of the
 * usual distance since the last job added to where it is; else the last job's reading plus the usual.
 */
private fun dueMetric(current: Double?, last: ComponentOccurrence, typical: TypicalInterval): Double? {
    val usual = typical.metric
    val since = last.metricSince
    return when {
        usual == null -> null
        current != null && since != null -> current + usual - since
        else -> last.metricAtTime?.let { it + usual }
    }
}

private const val HALF = 0.5

/** [value] rounded to the nearest whole number, a half away from zero (Swift's `rounded()`). */
private fun roundedAwayFromZero(value: Double): Double = if (value >= 0) floor(value + HALF) else ceil(value - HALF)
