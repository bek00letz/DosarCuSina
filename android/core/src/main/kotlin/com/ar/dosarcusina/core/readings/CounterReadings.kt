package com.ar.dosarcusina.core.readings

import com.ar.dosarcusina.core.values.MeasurementUnit
import java.time.Instant

/**
 * A reading a section keeps, as the engine reads it: the store fills one from each of the section's
 * `MeasurementLog`s. [key] is the store's own name for it (its row), handed back in what a step changes.
 */
data class StoredReading(
    val key: Long,
    val at: Instant,
    val value: Double,
    val unit: MeasurementUnit?,
    val kind: MeasurementKind,
    val startsCounter: Boolean = false,
    val basis: ReadingBasis? = null,
) {
    /** An estimate of the counter: it counts only until a later reading of its counter is lower. */
    val isEstimate: Boolean get() = basis == ReadingBasis.ESTIMATED

    /** The reading as the series reads it. */
    val reading: Reading get() = Reading(at, value, startsCounter, isEstimate)
}

/**
 * A reading a step will record, worked out before the step writes anything, as the iOS app's
 * `PlannedReading`: the step asks about it first ([CounterReadings.question]) and then records exactly
 * what it asked about ([CounterReadings.recording]), so a flow that wraps several actions asks the same
 * question. Made with [plan].
 */
class PlannedReading private constructor(
    val value: Double,
    val at: Instant,
    val source: ReadingSource,
    /** Its unit: the one given, else its kind's. */
    val unit: MeasurementUnit?,
    val kind: MeasurementKind,
    val name: String,
    /** How it was taken: read, for the person's own; what the paper says, for a document's; null when unsaid. */
    val basis: ReadingBasis?,
    /** Readings the step takes away before it records this one (a document filed again): they never make it ask. */
    val replaces: Set<Long>,
    /**
     * Whether a reading the step replaces started a new counter: this one takes its place and starts it
     * instead, so filing the same paper again never asks about the old counter. Worked out when the step
     * is planned, before anything is taken away.
     */
    val continuesCounter: Boolean,
) {
    /** An estimate is never stored, and neither is a number that isn't one. */
    val isStored: Boolean get() = source != ReadingSource.ESTIMATE && value.isFinite()

    companion object {
        /** Plans [value] at [at] on a section whose readings are [existing]: the one way a step plans a reading. */
        @Suppress("LongParameterList") // The iOS initializer's parts, each with its default.
        fun plan(
            value: Double,
            at: Instant,
            source: ReadingSource,
            unit: MeasurementUnit?,
            existing: List<StoredReading>,
            kind: MeasurementKind? = null,
            name: String = "",
            basis: ReadingBasis? = null,
            replaces: Set<Long> = emptySet(),
        ): PlannedReading {
            val chosen = kind ?: MeasurementKind.forUnit(unit)
            val kept = unit ?: chosen.defaultUnit
            val continues = chosen.isCumulative && existing.any {
                it.startsCounter && it.unit == kept && it.key in replaces
            }
            return PlannedReading(
                value = value, at = at, source = source, unit = kept, kind = chosen, name = name,
                basis = if (source == ReadingSource.PERSON) ReadingBasis.READ else basis,
                replaces = replaces, continuesCounter = continues,
            )
        }
    }
}

/**
 * What recording a planned reading does to a section's readings ([CounterReadings.recording]), for the
 * store to carry out in its step.
 */
sealed interface Recording {
    /** Nothing is stored: an estimate, or a number that isn't one. */
    data object NotStored : Recording

    /** It asks first, and nothing is written ([LowerReadingQuestion]). */
    data class Asks(val question: LowerReadingQuestion) : Recording

    /**
     * It records the reading, starting a counter when [startsCounter]; then takes away [removes]
     * ("Corectează citirea veche", once the new one is in, so a counter one of them started passes on to
     * it) and marks [marksEstimated] as estimates ("Era o estimare").
     */
    data class Records(
        val startsCounter: Boolean,
        val removes: List<StoredReading>,
        val marksEstimated: List<StoredReading>,
    ) : Recording
}

/**
 * The rules every way of recording, asking about and taking away a section's readings follows, as the
 * iOS app's `HouseholdMutations` readings (ios/DosarCuSina/Services/History/Readings.swift). Pure: the
 * store reads a section's readings into [StoredReading]s, asks here, and carries out the answer.
 */
object CounterReadings {
    /** The readings in [unit] (every unit when null), as the one cleaned series. */
    fun series(readings: List<StoredReading>, unit: MeasurementUnit?): ReadingSeries {
        val logs = readings.filter { unit == null || it.unit == unit }
        return ReadingSeries(logs.map { it.reading }, cumulative = logs.all { it.kind.isCumulative })
    }

    /** The section's value now: the series' last reading of the counter in use (a weight: the newest). */
    fun current(readings: List<StoredReading>, unit: MeasurementUnit?): Double? = series(readings, unit).current

    /**
     * The counter readings in [unit], counter by counter, in the series' order ([ReadingSeries.split]):
     * every reading, the ones a counter leaves out too.
     */
    fun counters(readings: List<StoredReading>, unit: MeasurementUnit?): List<List<StoredReading>> =
        ReadingSeries.split(
            readings.filter { it.kind.isCumulative && it.unit == unit },
            StoredReading::at, StoredReading::value, StoredReading::startsCounter,
        )

    /**
     * The reading that started the counter in use now ("Contor nou"), when the person said a new one
     * started; null while the section has had one counter.
     */
    fun counterStart(readings: List<StoredReading>, unit: MeasurementUnit?): StoredReading? =
        counters(readings, unit).lastOrNull()?.firstOrNull()?.takeIf { it.startsCounter }

    /**
     * The question recording [planned] raises, without changing anything: the one rule for a lower
     * counter, asked before a unit of work writes anything. A question when a counter reading is lower
     * than one recorded on or before its moment on the same counter and nobody has answered, with the
     * answers that fit, the likelier first ([ReadingDrop], [LowerReadingAnswer.offered]). None when every
     * higher reading is an estimate and the drop is small: the real index correcting them, which the
     * series follows by itself. None for no [planned] reading: the step records none.
     */
    fun question(
        planned: PlannedReading?,
        readings: List<StoredReading>,
        answer: LowerReadingAnswer?,
    ): LowerReadingQuestion? {
        if (planned == null || !planned.isStored || answer != null) return null
        val higher = higher(planned, readings)
        val highest = higher.maxByOrNull { it.value } ?: return null
        val around = readings.filter {
            it.unit == planned.unit && it.kind.isCumulative && it.key !in planned.replaces
        }
        val drop = ReadingDrop(highest.value, planned.value, ReadingSeries(around.map { it.reading }))
        if (drop.size == ReadingDrop.Size.SMALL && higher.all { it.isEstimate }) return null
        return LowerReadingQuestion(
            previous = highest.value,
            previousAt = highest.at,
            value = planned.value,
            unit = planned.unit,
            answers = LowerReadingAnswer.offered(planned.kind, likelyNewCounter = drop.size == ReadingDrop.Size.LARGE),
        )
    }

    /**
     * What recording [planned] with [answer] does to [readings]: the one way to record a reading.
     *
     * - An estimate is never stored ([Recording.NotStored]).
     * - A lower counter asks first ([question]); [LowerReadingAnswer.WAS_ESTIMATE] marks the higher
     *   earlier readings as estimates, [LowerReadingAnswer.CORRECT_OLD] takes them away,
     *   [LowerReadingAnswer.KEEP_ASIDE] keeps the new one, which the series then leaves aside, and
     *   [LowerReadingAnswer.NEW_COUNTER] makes the new one the first of a new counter.
     */
    fun recording(planned: PlannedReading, readings: List<StoredReading>, answer: LowerReadingAnswer?): Recording {
        if (!planned.isStored) return Recording.NotStored
        question(planned, readings, answer)?.let { return Recording.Asks(it) }
        val higher = higher(planned, readings)
        val startsNew = answer == LowerReadingAnswer.NEW_COUNTER && higher.isNotEmpty()
        return Recording.Records(
            startsCounter = planned.continuesCounter || startsNew,
            removes = if (answer == LowerReadingAnswer.CORRECT_OLD) higher else emptyList(),
            marksEstimated = if (answer == LowerReadingAnswer.WAS_ESTIMATE) {
                higher.filterNot { it.isEstimate }
            } else {
                emptyList()
            },
        )
    }

    /**
     * The reading that takes over the counter [deleted] started, when it goes: the next reading of the
     * same counter, so the counter stays as long as one of its readings does. Null when it started none,
     * or none of its readings is left (the change is then no longer known, and the next lower reading
     * asks again).
     */
    fun handsCounterTo(deleted: StoredReading, readings: List<StoredReading>): StoredReading? {
        if (!deleted.startsCounter) return null
        val counter = counters(readings, deleted.unit).firstOrNull { it.firstOrNull()?.key == deleted.key }
        return counter?.getOrNull(1)
    }

    /**
     * The counter readings recording [planned] would find higher than it: on its counter (from the newest
     * "Contor nou" on or before its moment), recorded on or before its moment, and not an estimate a
     * reading already kept corrected ([ReadingSeries.correctedEstimates]). What makes it ask first, and
     * what [LowerReadingAnswer.CORRECT_OLD] removes and [LowerReadingAnswer.WAS_ESTIMATE] marks. Readings
     * the step replaces first don't count, and a reading that takes the place of one that started a
     * counter starts it, so nothing comes before it.
     */
    fun higher(planned: PlannedReading, readings: List<StoredReading>): List<StoredReading> {
        if (!planned.kind.isCumulative || planned.continuesCounter) return emptyList()
        val all = readings.filter { it.unit == planned.unit && it.kind.isCumulative && it.key !in planned.replaces }
        val corrected = ReadingSeries.split(all, StoredReading::at, StoredReading::value, StoredReading::startsCounter)
            .flatMap { counter ->
                ReadingSeries.correctedEstimates(counter, StoredReading::value, StoredReading::isEstimate)
                    .map { counter[it].key }
            }
            .toSet()
        val logs = all.filter { it.at <= planned.at && it.key !in corrected }
        val start = logs.filter { it.startsCounter }.maxOfOrNull { it.at }
        return logs.filter { log -> log.value > planned.value && (start == null || log.at >= start) }
    }
}
