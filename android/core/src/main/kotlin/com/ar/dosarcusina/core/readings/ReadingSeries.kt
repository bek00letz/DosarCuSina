package com.ar.dosarcusina.core.readings

import java.time.Duration
import java.time.Instant

/**
 * A single timestamped counter observation, as the iOS app's `CadenceCalculator.TelemetryReading`.
 */
data class Reading(
    val at: Instant,
    val metric: Double,
    /** The first reading of a new counter: the readings from it on count on their own ([ReadingSeries.counters]). */
    val startsCounter: Boolean = false,
    /** An estimate of the counter: it counts only until a later reading of its counter is lower. */
    val isEstimate: Boolean = false,
) {
    /** The same reading, at the same moment and value, whether or not it starts a counter. */
    fun isSameReading(other: Reading): Boolean = at == other.at && metric == other.metric
}

/** How far the counters moved and over how many days, counter by counter ([ReadingSeries.progress]). */
data class Progress(val distance: Double, val days: Double)

/**
 * One cleaned series of counter readings, the only input to every rate and projection and to the hero
 * value, as the iOS app's `ReadingSeries` (ios/DosarCuSina/Services/History/Readings.swift). A counter
 * only goes up, so each counter's readings are the longest run that never goes down, in date order; on a
 * tie the earlier readings win. A reading left out (a typo, one kept aside) is skipped, never a reason to
 * stop projecting.
 *
 * A reading that starts a new counter ("Contor nou": a replaced meter or dashboard, one that went round)
 * splits the series: the readings from it on are the new counter's, the ones before stay as the old
 * one's ([counters]). The value now is the newest counter's; how far and how fast the counters moved is
 * added up counter by counter ([progress], [distance]), so a change of counter is never a drop or a jump.
 */
class ReadingSeries(raw: List<Reading>, cumulative: Boolean = true) {
    /** Each counter's readings that count, oldest counter first, each oldest first. */
    val counters: List<List<Reading>>

    /**
     * The readings that count, every counter's, oldest first. The first of each counter after the first
     * says it starts one, so a series made again from them splits the same way.
     */
    val readings: List<Reading>

    /** Readings that break the order of their counter and are left out. */
    val setAside: List<Reading>

    /**
     * Estimates a later reading of their counter is lower than ([correctedEstimates]): kept as history,
     * never counted, never flagged as breaking the order.
     */
    val corrected: List<Reading>

    /** When each counter after the first starts: the moment of the reading that started it. */
    val counterStarts: List<Instant>

    init {
        if (!cumulative) {
            val ordered = raw.sortedWith(compareBy<Reading> { it.at }.thenBy { it.metric })
            counters = if (ordered.isEmpty()) emptyList() else listOf(ordered)
            readings = ordered
            setAside = emptyList()
            corrected = emptyList()
            counterStarts = emptyList()
        } else {
            val split = split(raw, Reading::at, Reading::metric, Reading::startsCounter)
            val kept = ArrayList<List<Reading>>()
            val left = ArrayList<Reading>()
            val estimates = ArrayList<Reading>()
            for (counter in split) {
                val correctedPlaces = correctedEstimates(counter, Reading::metric, Reading::isEstimate).toSet()
                estimates += counter.filterIndexed { index, _ -> index in correctedPlaces }
                val run = longestRun(counter.filterIndexed { index, _ -> index !in correctedPlaces })
                kept += run.first
                left += run.second
            }
            counters = kept
            setAside = left
            corrected = estimates
            counterStarts = split.drop(1).mapNotNull { it.firstOrNull()?.at }
            readings = kept.flatMapIndexed { index, counter ->
                counter.mapIndexed { position, reading ->
                    reading.copy(startsCounter = index > 0 && position == 0)
                }
            }
        }
    }

    /** The counter now: the last reading of the newest counter. */
    val current: Double? get() = latest?.metric

    val latest: Reading? get() = counters.lastOrNull()?.lastOrNull()

    /**
     * How far the counters moved and over how many days, counter by counter: each counter's last reading
     * less its first, over the days between them, added up. The days between one counter's last reading
     * and the next one's first count for neither. Null when no counter has two readings. [days] measures
     * the time between two moments (in days of 24 hours unless told otherwise).
     */
    fun progress(days: (Instant, Instant) -> Double = ::daysBetween): Progress? {
        val measured = counters.filter { it.size >= 2 }
        if (measured.isEmpty()) return null
        var distance = 0.0
        var elapsed = 0.0
        for (counter in measured) {
            distance += counter.last().metric - counter.first().metric
            elapsed += days(counter.first().at, counter.last().at)
        }
        return Progress(distance, elapsed)
    }

    /**
     * How far the counter moved from [start] to [end] (each a value at a moment): on one counter, the
     * difference; across a new counter, what the old one moved after [start], every counter between it
     * whole, and what the new one moved up to [end]. Never below zero.
     */
    fun distance(start: Reading, end: Reading): Double {
        val first = counter(start.at)
        val last = counter(end.at)
        if (first >= last || first !in counters.indices || last !in counters.indices) {
            return maxOf(0.0, end.metric - start.metric)
        }
        var moved = maxOf(0.0, (counters[first].lastOrNull()?.metric ?: start.metric) - start.metric)
        for (index in (first + 1) until last) {
            val from = counters[index].firstOrNull() ?: continue
            moved += counters[index].last().metric - from.metric
        }
        moved += maxOf(0.0, end.metric - (counters[last].firstOrNull()?.metric ?: end.metric))
        return moved
    }

    /** The counter a value read at [at] belongs to: the newest one started on or before it. */
    fun counter(at: Instant): Int = counterStarts.count { it <= at }

    override fun equals(other: Any?): Boolean =
        other is ReadingSeries && counters == other.counters && readings == other.readings &&
            setAside == other.setAside && corrected == other.corrected && counterStarts == other.counterStarts

    override fun hashCode(): Int = counters.hashCode()

    override fun toString(): String = "ReadingSeries(counters=$counters, setAside=$setAside, corrected=$corrected)"

    companion object {
        private const val SECONDS_A_DAY = 86_400.0
        private const val NANOS_A_SECOND = 1e9

        /** The time between two moments in days of 24 hours, as the iOS app's `timeIntervalSince / 86_400`. */
        fun daysBetween(from: Instant, to: Instant): Double {
            val between = Duration.between(from, to)
            return (between.seconds + between.nano / NANOS_A_SECOND) / SECONDS_A_DAY
        }

        /**
         * Readings in the one order every counter is read in, split where a new counter starts: by date, a
         * reading that starts a counter first among those at the same moment, then by value. The one rule
         * for the series, for the question a lower reading asks and for the repairs.
         */
        fun <T> split(
            items: List<T>,
            at: (T) -> Instant,
            metric: (T) -> Double,
            startsCounter: (T) -> Boolean,
        ): List<List<T>> {
            val ordered = items.sortedWith(
                compareBy<T> { at(it) }.thenBy { if (startsCounter(it)) 0 else 1 }.thenBy { metric(it) },
            )
            val counters = ArrayList<MutableList<T>>()
            for (item in ordered) {
                if (counters.isEmpty() || startsCounter(item)) {
                    counters += mutableListOf(item)
                } else {
                    counters.last() += item
                }
            }
            return counters
        }

        /**
         * The estimates among one counter's readings, in the series' order ([split]), that a later reading
         * of the counter is lower than, by their place: a bill's estimated index once the real one comes in
         * below it, or an estimate the provider lowered since. They count no more; the readings that
         * corrected them do. The one rule for the series and for the question a lower reading asks.
         */
        fun <T> correctedEstimates(ordered: List<T>, metric: (T) -> Double, isEstimate: (T) -> Boolean): List<Int> {
            var lowestAfter = Double.POSITIVE_INFINITY
            val corrected = ArrayList<Int>()
            for (index in ordered.indices.reversed()) {
                if (isEstimate(ordered[index]) && lowestAfter < metric(ordered[index])) corrected += index
                lowestAfter = minOf(lowestAfter, metric(ordered[index]))
            }
            return corrected.reversed()
        }

        /** The longest run of [ordered] that never goes down (ties keep the earlier readings), and what is left out. */
        private fun longestRun(ordered: List<Reading>): Pair<List<Reading>, List<Reading>> {
            if (ordered.size <= 1) return ordered to emptyList()
            val length = IntArray(ordered.size) { 1 }
            val previous = IntArray(ordered.size) { -1 }
            for (i in ordered.indices) {
                for (j in 0 until i) {
                    if (ordered[j].metric <= ordered[i].metric && length[j] + 1 > length[i]) {
                        length[i] = length[j] + 1
                        previous[i] = j
                    }
                }
            }
            var end = 0
            for (i in ordered.indices) if (length[i] > length[end]) end = i
            val kept = HashSet<Int>()
            var index = end
            while (index >= 0) {
                kept += index
                index = previous[index]
            }
            return ordered.filterIndexed { place, _ -> place in kept } to
                ordered.filterIndexed { place, _ -> place !in kept }
        }
    }
}
