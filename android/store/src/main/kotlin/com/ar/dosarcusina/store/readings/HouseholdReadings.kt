package com.ar.dosarcusina.store.readings

import com.ar.dosarcusina.core.readings.CounterReadings
import com.ar.dosarcusina.core.readings.LowerReadingAnswer
import com.ar.dosarcusina.core.readings.LowerReadingQuestion
import com.ar.dosarcusina.core.readings.MeasurementKind
import com.ar.dosarcusina.core.readings.PlannedReading
import com.ar.dosarcusina.core.readings.ReadingBasis
import com.ar.dosarcusina.core.readings.ReadingSeries
import com.ar.dosarcusina.core.readings.ReadingSource
import com.ar.dosarcusina.core.readings.Recording
import com.ar.dosarcusina.core.readings.StoredReading
import com.ar.dosarcusina.core.values.MeasurementUnit
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.StepQuestion
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.MeasurementLog
import java.time.Instant

/** What the reading measures (`MeasurementLog.kind`); a kind a newer build wrote reads as custom. */
val MeasurementLog.kind: MeasurementKind get() = MeasurementKind.stored(kindRaw)

/** Its unit, read from any form it was stored in; null when it has none (`MeasurementLog.measurementUnit`). */
val MeasurementLog.measurementUnit: MeasurementUnit? get() = MeasurementUnit.of(unit)

/** How it was taken; null when nothing says, or for a key a newer build wrote (`MeasurementLog.basis`). */
val MeasurementLog.basis: ReadingBasis? get() = ReadingBasis.stored(basisRaw)

/** An estimate of the counter: it counts only until a later reading of its counter is lower. */
val MeasurementLog.isEstimate: Boolean get() = basis == ReadingBasis.ESTIMATED

/** The reading as the engine reads it, named by its row. */
val MeasurementLog.stored: StoredReading
    get() = StoredReading(pk, recordedAt, value, measurementUnit, kind, startsCounter, basis)

/**
 * Thrown when a counter reading is lower than one recorded before it and nobody has answered yet,
 * before the step writes anything (the iOS app's `LowerReadingQuestion`, a `StepQuestion`). A screen
 * asks [question] and saves again with the answer; nothing was saved.
 */
class LowerReadingAsked(val question: LowerReadingQuestion) :
    Exception("A counter reading lower than an earlier one asks first"), StepQuestion

/**
 * A reading a step will record on [asset] (its row), planned before the step writes anything: the
 * same reading the step asks about and then records ([HouseholdReadings.plan]).
 */
class PlannedSectionReading(val asset: Long, val reading: PlannedReading)

/**
 * The one way the binder records, asks about and takes away a section's readings, as the reading part of
 * the iOS app's `HouseholdMutations`
 * (ios/DosarCuSina/Services/History/Readings.swift and AssetActions.swift). The rules are the engine's
 * ([CounterReadings]); this reads a section's readings out of the binder and carries out the answer in a
 * step, and keeps the hero value equal to the readings ([HeroMetric]). Nothing here saves: the unit of
 * work the step belongs to does.
 */
// The reading part of HouseholdMutations, one function per job, as there.
@Suppress("TooManyFunctions")
object HouseholdReadings {
    // Reading

    /** The section's readings, in row order. */
    fun readings(view: BinderView, asset: Long): List<MeasurementLog> =
        view.pointingAt(Tables.readings, "asset", asset).mapNotNull { view.row(Tables.readings, it) }

    private fun stored(view: BinderView, asset: Long): List<StoredReading> = readings(view, asset).map { it.stored }

    /** The section's readings in [unit] (every unit when null), as the one cleaned series. */
    fun readingSeries(view: BinderView, asset: Long, unit: MeasurementUnit?): ReadingSeries =
        CounterReadings.series(stored(view, asset), unit)

    /**
     * The section's counter readings in [unit], counter by counter, in the series' order: every reading,
     * the ones a counter leaves out too.
     */
    fun counters(view: BinderView, asset: Long, unit: MeasurementUnit?): List<List<MeasurementLog>> {
        val rows = readings(view, asset).associateBy { it.pk }
        return CounterReadings.counters(rows.values.map { it.stored }, unit).map { counter ->
            counter.map { rows.getValue(it.key) }
        }
    }

    /** The reading that started the counter in use now ("Contor nou"); null while the section has had one counter. */
    fun counterStart(view: BinderView, asset: Long, unit: MeasurementUnit?): MeasurementLog? =
        CounterReadings.counterStart(stored(view, asset), unit)?.let { view.row(Tables.readings, it.key) }

    // Planning and asking

    /**
     * Plans [value] at [at] on [asset], from the readings it has in [view]: the one way an action plans
     * the reading it records. [replaces] names readings the step takes away first (a document filed
     * again), which never make it ask.
     */
    @Suppress("LongParameterList") // The iOS PlannedReading's parts, each with its default.
    fun plan(
        view: BinderView,
        asset: Long,
        value: Double,
        at: Instant,
        source: ReadingSource,
        unit: MeasurementUnit?,
        kind: MeasurementKind? = null,
        name: String = "",
        basis: ReadingBasis? = null,
        replaces: (MeasurementLog) -> Boolean = { false },
    ): PlannedSectionReading {
        val rows = readings(view, asset)
        val reading = PlannedReading.plan(
            value = value, at = at, source = source, unit = unit, existing = rows.map { it.stored },
            kind = kind, name = name, basis = basis,
            replaces = rows.filter(replaces).mapTo(mutableSetOf()) { it.pk },
        )
        return PlannedSectionReading(asset, reading)
    }

    /**
     * Asks the question recording [planned] raises, without changing anything: the one rule for a lower
     * counter, which every action calls before its unit of work opens ([StepQuestion]). Throws
     * [LowerReadingAsked] when [answer] is null and a counter reading is lower than one recorded on or
     * before its moment on the same counter ([CounterReadings.question]). Null [planned]: the step
     * records none.
     */
    fun askAboutReading(view: BinderView, planned: PlannedSectionReading?, answer: LowerReadingAnswer?) {
        planned ?: return
        val question = CounterReadings.question(planned.reading, stored(view, planned.asset), answer)
        if (question != null) throw LowerReadingAsked(question)
    }

    // Recording

    /**
     * Records [planned] in [step], as it was asked about before the unit opened: the one way to record
     * a reading on a section, for every action. Gives the reading kept, or null for an estimate.
     *
     * - A lower counter asks first ([askAboutReading]); an action asks before its unit writes anything,
     *   so inside a unit this only finds the question answered, or none to ask.
     * - [LowerReadingAnswer.WAS_ESTIMATE] marks the higher earlier readings as estimates;
     *   [LowerReadingAnswer.CORRECT_OLD] takes them away (and the visit readings that logged them), once
     *   the new one is in, so a counter one of them started passes on to it;
     *   [LowerReadingAnswer.KEEP_ASIDE] keeps the new one aside; [LowerReadingAnswer.NEW_COUNTER] makes it
     *   the first of a new counter.
     * - The reading keeps how it was taken ([PlannedReading.basis]), and is an example when its section
     *   is, unless [isExample] says.
     * - The hero value is then worked out from the readings ([HeroMetric.sync]).
     */
    fun recordReading(
        step: Step,
        planned: PlannedSectionReading,
        answer: LowerReadingAnswer?,
        isExample: Boolean? = null,
    ): MeasurementLog? {
        val asset = requireNotNull(step.row(Tables.assets, planned.asset)) { "No section in row ${planned.asset}" }
        val reading = planned.reading
        val recording = CounterReadings.recording(reading, stored(step, asset.pk), answer)
        if (recording is Recording.Asks) throw LowerReadingAsked(recording.question)
        if (recording !is Recording.Records) return null
        val log = step.insert(
            MeasurementLog(
                kindRaw = reading.kind.raw,
                name = reading.name,
                value = reading.value,
                unit = reading.unit?.key.orEmpty(),
                recordedAt = reading.at,
                isExample = isExample ?: asset.isExample,
                startsCounter = recording.startsCounter,
                basisRaw = reading.basis?.raw,
                asset = asset.pk,
            ),
        )
        for (old in recording.removes) step.row(Tables.readings, old.key)?.let { removeReading(step, it, asset.pk) }
        for (old in recording.marksEstimated) {
            step.row(Tables.readings, old.key)?.let { step.update(it.copy(basisRaw = ReadingBasis.ESTIMATED.raw)) }
        }
        HeroMetric.sync(step, asset.pk)
        return log
    }

    // Taking away

    /**
     * Takes back the reading a record of history recorded (a visit, "Gata"): the readings with the
     * record's moment and number, then works the hero value out again.
     */
    fun removeReading(step: Step, recordedBy: HistoryEntry) {
        val asset = recordedBy.asset ?: return
        if (recordedBy.metricReading == null) return
        for (log in readings(step, asset)) if (isReading(log, recordedBy)) deleteReading(step, log)
        HeroMetric.sync(step, asset)
    }

    /** Whether [log] is the reading [entry] recorded: its moment and its number, on its section. */
    fun isReading(log: MeasurementLog, entry: HistoryEntry): Boolean {
        val reading = entry.metricReading ?: return false
        return log.recordedAt == entry.occurredAt && log.value == reading && log.asset == entry.asset
    }

    /** Removes a wrong reading, and the same number on the visit that logged it; the hero value isn't worked out. */
    fun removeReading(step: Step, log: MeasurementLog, asset: Long) {
        for (row in step.pointingAt(Tables.history, "asset", asset)) {
            val entry = step.row(Tables.history, row) ?: continue
            if (entry.occurredAt == log.recordedAt && entry.metricReading == log.value) {
                step.update(entry.copy(metricReading = null))
            }
        }
        deleteReading(step, log)
    }

    /**
     * The one way a reading goes. A reading that started a new counter hands that on to the next reading
     * of the same counter ([CounterReadings.handsCounterTo]), so the counter stays as long as one of its
     * readings does. Doesn't work the hero value out again.
     */
    fun deleteReading(step: Step, log: MeasurementLog) {
        val current = step.row(Tables.readings, log.pk) ?: return
        val asset = current.asset
        if (asset != null) {
            CounterReadings.handsCounterTo(current.stored, stored(step, asset))
                ?.let { step.row(Tables.readings, it.key) }
                ?.let { step.update(it.copy(startsCounter = true)) }
        }
        step.delete(current)
    }
}
