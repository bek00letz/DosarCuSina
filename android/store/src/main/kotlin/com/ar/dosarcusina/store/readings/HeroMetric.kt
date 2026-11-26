package com.ar.dosarcusina.store.readings

import com.ar.dosarcusina.archive.v3.FieldDefinition
import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.core.values.MeasurementUnit
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.repairs.RepairReading
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.keptValues
import com.ar.dosarcusina.store.schema.withKeptValues

/**
 * A section's hero value worked out from its readings, as the iOS app's `HouseholdMutations.syncHeroMetric`
 * and `heroMetricField`: the hero number field (the kilometres) shows what the readings say, never a value
 * of its own. Readings are the source of truth.
 */
object HeroMetric {
    /** The category's hero number field: a counter or a measured value with a unit. */
    fun field(fields: List<FieldDefinition>): FieldDefinition? = fields.firstOrNull {
        it.role == HERO_METRIC && (it.type == METRIC || it.type == NUMBER) && MeasurementUnit.of(it.unit) != null
    }

    /** The hero field's value among [values]. */
    fun value(values: FieldValues, fields: List<FieldDefinition>): Double? =
        field(fields)?.let { (values[it.key] as? FieldValue.Number)?.value }

    /** The hero field's unit. */
    fun unit(fields: List<FieldDefinition>): MeasurementUnit? = field(fields)?.unit?.let(MeasurementUnit::of)

    /** The fields of [asset]'s category as kept in the binder; empty when its record isn't there. */
    fun categoryFields(view: BinderView, asset: Asset): List<FieldDefinition> =
        RepairReading.categories(view)[asset.templateKey]?.let(RepairReading::fields).orEmpty()

    /**
     * The value the hero field should show, when it differs from what it shows: for a counter, the last
     * reading of the cleaned series (of the counter in use); for anything else (a weight), the newest.
     * Null when it shows that already, or there are no readings in its unit, or no hero field.
     */
    fun mismatch(view: BinderView, asset: Asset): HeroMismatch? {
        val field = field(categoryFields(view, asset)) ?: return null
        val series = HouseholdReadings.readingSeries(view, asset.pk, MeasurementUnit.of(field.unit))
        val current = series.current ?: return null
        val shown = (asset.keptValues.value[field.key] as? FieldValue.Number)?.value
        return if (shown == current) null else HeroMismatch(field, shown, current)
    }

    /** A hero field that doesn't show what the readings say: what it shows and what it should. */
    data class HeroMismatch(val field: FieldDefinition, val shown: Double?, val current: Double)

    /**
     * Keeps the hero field equal to the readings ([mismatch]). Leaves it alone when there are no
     * readings in its unit. Readings are the source of truth.
     */
    fun sync(step: Step, asset: Long) {
        val section = step.row(Tables.assets, asset) ?: return
        val mismatch = mismatch(step, section) ?: return
        val kept = section.keptValues
        val values = kept.value.with(mismatch.field.key, FieldValue.Number(mismatch.current))
        step.update(section.withKeptValues(kept.replacingValue(values)))
    }

    private const val HERO_METRIC = "heroMetric"
    private const val METRIC = "metric"
    private const val NUMBER = "number"
}
