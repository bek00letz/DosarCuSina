package com.ar.dosarcusina.store.readings

import com.ar.dosarcusina.archive.binder.BuiltIns
import com.ar.dosarcusina.catalog.Catalog
import com.ar.dosarcusina.core.readings.LowerReadingAnswer
import com.ar.dosarcusina.core.readings.MeasurementKind
import com.ar.dosarcusina.core.readings.ReadingSource
import com.ar.dosarcusina.core.values.MeasurementUnit
import com.ar.dosarcusina.store.BinderSnapshot
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.UndoReceipt
import com.ar.dosarcusina.store.UnitOfWork
import com.ar.dosarcusina.store.examples.ExampleOwnership
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.MeasurementLog
import kotlinx.coroutines.runBlocking
import java.time.Instant

/**
 * The section actions that record or change a reading on their own, as the reading part of the iOS app's
 * `AssetActions` (ios/DosarCuSina/Services/Obligations/AssetActions.swift): a counter read today, a
 * measured value, and "Nu e contor nou". The rest of `AssetActions` (making, editing, moving and deleting
 * a section) builds on these, never beside them.
 *
 * Every question comes first, before the unit of work opens ([ExampleOwnership.requireReal],
 * [HouseholdReadings.askAboutReading]), so a step that asks has written nothing.
 */
class AssetReadingActions(
    private val unitOfWork: UnitOfWork,
    /** The moment a reading is recorded at when nothing else says, and every step's clock. */
    private val now: () -> Instant = unitOfWork.clock,
    /** The app's own categories, for the gender of an example's question. */
    private val builtIns: BuiltIns = Catalog.builtIn,
) {
    /**
     * Records a counter reading on its own (the kilometres read today) in the unit of the section's hero
     * field, through the one path: an estimate is never stored, a lower counter asks first, and the hero
     * value follows the readings. Gives the reading kept, or null for an estimate.
     */
    fun recordReading(
        asset: Asset,
        value: Double,
        source: ReadingSource,
        at: Instant? = null,
        lowerReading: LowerReadingAnswer? = null,
    ): MeasurementLog? {
        val view = snapshot()
        val section = current(view, asset)
        val unitOfField = HeroMetric.unit(HeroMetric.categoryFields(view, section))
        // Every question first, before anything is written (`StepQuestion`).
        val isExample = ExampleOwnership.requireReal(view, section, builtIns)
        val planned = HouseholdReadings.plan(view, section.pk, value, at ?: now(), source, unitOfField)
        HouseholdReadings.askAboutReading(view, planned, lowerReading)
        if (!planned.reading.isStored) return null
        return unitOfWork.perform(now = now()) { step ->
            HouseholdReadings.recordReading(step, planned, lowerReading, isExample)
        }
    }

    /**
     * Records a measured value of any kind (a meter index, a weight, a lab value) through the one reading
     * path. Counter readings also update the hero value. [asExample] only for the example loader.
     */
    @Suppress("LongParameterList") // The iOS action's parts, each with its default.
    fun recordMeasurement(
        asset: Asset,
        kind: MeasurementKind,
        value: Double,
        unit: MeasurementUnit? = null,
        name: String = "",
        at: Instant? = null,
        asExample: Boolean = false,
        lowerReading: LowerReadingAnswer? = null,
    ): MeasurementLog {
        val view = snapshot()
        val section = current(view, asset)
        val isExample = ExampleOwnership.requireReal(view, section, builtIns, creatingExample = asExample)
        val planned = HouseholdReadings.plan(
            view, section.pk, value, at ?: now(), ReadingSource.PERSON, unit, kind = kind, name = name,
        )
        HouseholdReadings.askAboutReading(view, planned, lowerReading)
        return unitOfWork.perform(now = now()) { step ->
            // Only an estimate gives none, and this records what was measured.
            requireNotNull(HouseholdReadings.recordReading(step, planned, lowerReading, isExample)) {
                "A measured value is a number"
            }
        }
    }

    /**
     * "Nu e contor nou": the reading the person once said started a new counter doesn't. The readings in
     * its unit count as one counter again (the lower ones then set aside, as the series sets aside any
     * reading that breaks the order), and the hero value follows them. One undoable step; nothing is
     * deleted.
     */
    fun notANewCounter(start: MeasurementLog): UndoReceipt = unitOfWork.performUndoable(now = now()) { step ->
        val log = requireNotNull(step.row(Tables.readings, start.pk)) { "The reading is gone" }
        step.update(log.copy(startsCounter = false))
        log.asset?.let { HeroMetric.sync(step, it) }
    }.receipt

    private fun snapshot(): BinderView = runBlocking { BinderSnapshot.read(unitOfWork.store.database) }

    private fun current(view: BinderView, asset: Asset): Asset =
        requireNotNull(view.row(Tables.assets, asset.pk)) { "No section in row ${asset.pk}" }
}
